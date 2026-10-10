# frozen_string_literal: true

require 'csv'
require 'digest'
require 'fileutils'
require 'json'
require 'securerandom'
require 'tmpdir'
require 'uri'

module Lexicon
  module Contribution
    module Web
      # The local web interface of `./lexicon contribute --web`: a contributor drops a table, its columns
      # and their types are detected, the sheet is a form, and the review is read again each time a file
      # changes. It knows nothing of sockets: a request comes in, a response goes out.
      class App
        Request = Struct.new(:verb, :path, :headers, :body, keyword_init: true)
        Response = Struct.new(:status, :headers, :body, keyword_init: true)

        LOCAL_HOSTS = %w[localhost 127.0.0.1 [::1]].freeze
        TOKEN_HEADER = 'x-lexicon-token'
        # Tables whose review is kept
        MEMORISED = 200
        # A table larger than this is read once the request is answered: no request waits for a long reading,
        # which a proxy in front would cut. The page asks until it is read.
        BACKGROUND_ABOVE = 2 * 1024 * 1024
        # Reading a large table takes hundreds of megabytes: one at a time, whoever asks
        READING = Mutex.new
        # Online, what the holder of a key may keep on the server
        HOSTED_DATASETS = 20
        # File that marks a dataset as proposed to the maintainers; it holds the date
        PROPOSED = 'proposed'
        SHEET_FIELDS = %w[description author personal_data].freeze
        SOURCE_FIELDS = %w[name url provider licence licence_url date].freeze

        # @return [String] what a form or a script of the pages must give back to change anything
        attr_reader :token

        # @param [Pathname] root directory holding one directory per contribution
        # @param [Array<String>] taken names of the datasources that already exist
        # @param [String] token
        # @param [Pathname, nil] raw root of the raw directories, where a large table is kept
        # @param [String] prefix path the pages are served under, when a proxy stands in front
        # @param [Boolean] hosted served online to the holder of a key (see Hosted): any host name is answered,
        #   and a dataset is proposed from its page
        # @param [Integer] maximum_upload size of the largest table accepted, in bytes
        def initialize(root:, taken: [], token: SecureRandom.hex(16), raw: nil, prefix: '', hosted: false,
                       maximum_upload: Server::MAXIMUM_BODY)
          @root = root
          @maximum_upload = maximum_upload
          # Tables arriving in parts, and those being read after their request was answered
          @uploads = {}
          @workers = []
          @raw = raw
          @prefix = prefix.chomp('/')
          @hosted = hosted
          @taken = taken
          @token = token
          @pages = Pages.new
          # What the last import of each dataset did, said on its page until the contributor has read it
          @imports = {}
          # What the review found in each table, so that filling the sheet does not read a large table again
          @memo = {}
        end

        # @param [Request] request
        # @return [Response]
        def call(request)
          return text(403, 'Cette interface ne répond que sur ce poste.') unless @hosted || local?(request)

          segments = request.path.split('?').first.split('/').reject(&:empty?).map { |segment| URI.decode_www_form_component(segment) }
          return refused if request.verb != 'GET' && !allowed?(request)

          route(request, segments) || text(404, 'Cette page n’existe pas.')
        end

        # Waits for the tables being read in the background.
        def settle
          @workers.shift.join until @workers.empty?
        end

        # @return [Boolean] whether datasets can be created and changed from the pages
        def writable?
          @root.directory? && @root.writable?
        end

        private

          def route(request, segments)
            verb = request.verb
            section, name, part, file = segments
            return verb == 'GET' ? html(@pages.index(summaries, context)) : nil if segments.empty?
            return nil unless section == 'jeux'
            return verb == 'POST' ? create(form(request)['name'].to_s.strip) : nil if segments.size == 1

            with(name) { |dir| route_dataset(request, dir, [verb, part, segments.size], file) }
          end

          def route_dataset(request, dir, shape, file)
            case shape
            when ['GET', nil, 2] then html(@pages.dataset(state(dir), context))
            when ['GET', 'empreinte', 3] then text(200, fingerprint(dir))
            when ['GET', 'etat', 3] then live(dir)
            when ['POST', 'fiche', 3] then save_sheet(dir, form(request))
            when ['POST', 'detecter', 3] then detect(dir, form(request)['file'].to_s)
            when ['POST', 'lu', 3] then read(dir)
            when ['PUT', 'fichiers', 4] then receive(dir, file, request)
            when ['POST', 'proposer', 3] then propose(dir, true)
            when ['POST', 'retirer', 3] then propose(dir, false)
            end
          end

          def context
            { token: @token, writable: writable?, root: @root, prefix: @prefix, hosted: @hosted }
          end

          # The name of a host is checked so that another site cannot reach this one under its own name
          def local?(request)
            host = request.headers['host'].to_s.sub(/:\d+\z/, '')

            LOCAL_HOSTS.include?(host)
          end

          def allowed?(request)
            given = request.headers[TOKEN_HEADER] || form(request)['token']

            writable? && !given.nil? && given == @token
          end

          def refused
            text(403, writable? ? 'Cette page est périmée : la recharger.' : 'Le dossier des contributions est en lecture seule.')
          end

          def form(request)
            return {} unless request.headers['content-type'].to_s.start_with?('application/x-www-form-urlencoded')

            URI.decode_www_form(request.body.to_s.dup.force_encoding(Encoding::UTF_8)).to_h
          rescue ArgumentError
            {}
          end

          def datasets
            Sheet.directories(@root)
          end

          def summaries
            datasets.map { |dir| summary(dir) }
          end

          # A dataset is looked for among those that exist: a name never becomes a path by itself
          def with(name)
            dir = datasets.find { |candidate| candidate.basename.to_s == name }

            dir.nil? ? nil : yield(dir)
          end

          def create(name)
            problem = if !name.match?(Scaffold::VALID_NAME)
                        "« #{name} » : le nom d'un jeu est en minuscules, sans accent ni espace, comme releves_sol."
                      elsif @taken.include?(name) || @root.join(name).exist?
                        "Un jeu s'appelle déjà « #{name} »."
                      elsif @hosted && datasets.size >= HOSTED_DATASETS
                        "Vous avez déjà #{HOSTED_DATASETS} jeux ici : en retirer un, ou écrire à OSFarm."
                      end
            return html(@pages.index(summaries, context, problem: problem), status: 422) if problem

            @root.join(name).mkpath
            Sheet.write(@root.join(name), Scaffold.new.blank)
            redirect("#{@prefix}/jeux/#{name}")
          end

          # Online only, and only for a dataset the review accepts: the maintainers look for this mark
          def propose(dir, proposed)
            return nil unless @hosted

            mark = dir.join(PROPOSED)
            if !proposed
              FileUtils.rm_f(mark)
            elsif review_of(dir)[:errors].empty? && review_of(dir)[:unreadable].nil?
              mark.write("#{Time.now.utc.strftime('%Y-%m-%d')}\n")
            end
            live(dir)
          end

          # @return [String, nil] the day the dataset was proposed
          def proposed(dir)
            mark = dir.join(PROPOSED)

            mark.file? ? mark.read.strip[0, 10] : nil
          end

          # The parts of the page of a dataset, for the page to replace them where it stands
          def live(dir)
            json(@pages.parts(state(dir), context))
          end

          # The contributor has read what the last import did
          def read(dir)
            @imports.delete(dir.basename.to_s)
            live(dir)
          end

          # The form of the page, or the sheet itself when the contributor writes it by hand
          def save_sheet(dir, fields)
            if fields.key?('sheet')
              dir.join(Sheet::FILE).write(fields['sheet'].gsub("\r\n", "\n"))
            else
              Sheet.write(dir, filled(Sheet.load(dir).data, fields))
            end
            live(dir)
          rescue Psych::Exception
            live(dir)
          end

          # @return [Hash] the sheet, with what the form says
          def filled(data, fields)
            put = ->(hash, key, value) { value.to_s.strip.empty? ? hash.delete(key) : hash[key] = value.strip }
            source = data['source'].is_a?(Hash) ? data['source'] : {}

            SHEET_FIELDS.each { |field| put.call(data, field, fields[field]) }
            SOURCE_FIELDS.each { |field| put.call(source, field, fields["source_#{field}"]) }
            put.call(data, 'scope', fields['members'] == '1' ? 'members' : nil)
            entries = data['tables'].is_a?(Array) ? data['tables'] : []

            data.merge('source' => source, 'tables' => entries.each_with_index.map { |entry, index| described(entry, index, fields) })
          end

          # @return [Hash] the entry of a table, with the types, the key and the links the form chose
          def described(entry, index, fields)
            return entry unless entry.is_a?(Hash) && entry['columns'].is_a?(Hash)

            columns = entry['columns'].to_h do |column, type|
              chosen = fields["type|#{index}|#{column}"]
              [column, Sheet::TYPES.key?(chosen) ? chosen : type]
            end
            pivots = columns.keys.map { |column| [column, fields["pivot|#{index}|#{column}"]] }
                            .select { |_, key| Packaging::Pivots::KEYS.key?(key) || Sheet::PLACE_PARTS.key?(key) }.to_h
            key = columns.key?(fields["key|#{index}"]) ? fields["key|#{index}"] : entry['key']
            kept = entry.reject { |field, _| field == 'pivots' }

            kept.merge('key' => key, 'columns' => columns).merge(pivots.empty? ? {} : { 'pivots' => pivots })
          end

          # A table comes whole, or in parts when it is large: `?morceau=<index>&sur=<count>`
          def receive(dir, file, request)
            query = URI.decode_www_form(request.path.split('?', 2)[1].to_s).to_h
            part, parts = query.values_at('morceau', 'sur').map { |value| Integer(value.to_s, 10, exception: false) }

            parts.nil? || part.nil? ? answer_import(dir, file, request.body) : receive_part(dir, file, request.body, part, parts)
          rescue ArgumentError
            answer_import(dir, file, request.body)
          end

          # Parts are kept out of the dataset until the last one: a half-sent table is never read
          def receive_part(dir, file, content, part, parts)
            unless Import::EXTENSIONS.include?(File.extname(file).downcase)
              return text(422, "« #{file} » : ce format n'est pas lu. Formats lus : #{Import::EXTENSIONS.join(', ')}.")
            end

            key = [dir.to_s, file]
            @uploads[key] = { expected: 0, path: Pathname.new(Dir.tmpdir).join("lexicon-upload-#{SecureRandom.hex(12)}") } if part.zero?
            upload = @uploads[key]
            return interrupted(key, file) if upload.nil? || upload[:expected] != part || part >= parts

            File.open(upload[:path], part.zero? ? 'wb' : 'ab') { |stored| stored.write(content) }
            upload[:expected] += 1
            return too_large(key, file) if upload[:path].size > @maximum_upload
            return json({ part: part }) if part < parts - 1

            content = upload[:path].binread
            forget(key)
            background(dir, file) { import(dir, file, content) }
          end

          def interrupted(key, file)
            forget(key)
            text(409, "L'envoi de « #{file} » a été interrompu : déposer de nouveau le tableau.")
          end

          def too_large(key, file)
            forget(key)
            text(413, "« #{file} » dépasse #{@maximum_upload / (1024 * 1024)} Mo : c'est le plus gros tableau accepté ici.")
          end

          def forget(key)
            upload = @uploads.delete(key)
            FileUtils.rm_f(upload[:path]) unless upload.nil?
          end

          # Answers at once that the table is being read; what was found, or why it could not be read, is
          # said by the page when it asks again
          def background(dir, file)
            name = dir.basename.to_s
            @imports[name] = { file: file, notes: [], problem: nil, pending: true }
            @workers << Thread.new do
              READING.synchronize { yield }
            rescue Import::Unreadable => e
              @imports[name] = { file: file, notes: [], problem: e.message }
            rescue Psych::Exception
              @imports[name] = { file: file, notes: [], problem: 'La fiche ne se lit pas : la corriger d’abord.' }
            rescue StandardError => e
              @imports[name] = { file: file, notes: [], problem: "« #{file} » n'a pas pu être lu : #{e.message}" }
            end
            live(dir)
          end

          def answer_import(dir, file, content)
            return background(dir, file) { import(dir, file, content) } if content.bytesize > BACKGROUND_ABOVE

            import(dir, file, content)
            live(dir)
          rescue Import::Unreadable => e
            text(422, e.message)
          rescue Psych::Exception
            text(422, 'La fiche ne se lit pas : la corriger d’abord, sous « Fiche en YAML ».')
          end

          # A file already in the directory, dropped there by hand
          def detect(dir, name)
            file = dir.children.find { |child| child.file? && child.basename.to_s == name }
            return nil if file.nil?
            return background(dir, name) { import(dir, name, file.binread) } if file.size > BACKGROUND_ABOVE

            import(dir, name, file.binread)
            live(dir)
          rescue Import::Unreadable, Psych::Exception => e
            problem = e.is_a?(Import::Unreadable) ? e.message : 'La fiche ne se lit pas : la corriger d’abord.'
            @imports[dir.basename.to_s] = { file: name, notes: [], problem: problem }
            live(dir)
          end

          # Writes the table as a contribution expects it, and describes it in the sheet. Tables whose file
          # is gone leave the sheet: a contributor who replaces a file does not have to tidy up.
          def import(dir, name, content)
            sheet = Sheet.load(dir, raw: @raw)
            data = sheet.data
            result = Import.new(name, content).result
            entries = (data['tables'].is_a?(Array) ? data['tables'] : []).select { |entry| entry.is_a?(Hash) }
            former = entries.find { |entry| entry['file'] == result.file } || {}
            entry = former.slice('table').merge('file' => result.file, 'key' => result.key, 'columns' => result.columns)
            entry['pivots'] = result.pivots unless result.pivots.empty?
            present = sheet.tables.select { |table| sheet.path(table).file? }.map(&:file)
            kept = entries.select { |other| other['file'] != result.file && present.include?(other['file'].to_s.strip) }

            dir.join(result.file).write(result.csv)
            Sheet.write(dir, data.merge('tables' => [*kept, entry]))
            @imports[dir.basename.to_s] = { file: result.file, notes: result.notes, problem: nil }
          end

          # @return [Hash] what the list says of a dataset
          def summary(dir)
            review = review_of(dir)

            { name: dir.basename.to_s, errors: review[:errors].size, warnings: review[:warnings].size, unreadable: review[:unreadable],
              proposed: proposed(dir) }
          end

          # @return [Hash] everything the page of a dataset shows
          def state(dir)
            review = review_of(dir)
            tables = review[:sheet] ? review[:sheet].tables : []

            review.merge(name: dir.basename.to_s, raw: dir.join(Sheet::FILE).read(encoding: 'bom|utf-8').scrub,
                         tables: tables.map { |table| table.to_h.merge(preview: preview(review[:sheet].path(table))) },
                         loose: loose(dir, tables.map(&:file)), import: @imports[dir.basename.to_s], fingerprint: fingerprint(dir),
                         proposed: proposed(dir))
          end

          # @return [Array<String>] files of the directory that could be tables and that the sheet does not describe
          def loose(dir, described)
            files = dir.children.select { |child| child.file? && Import::EXTENSIONS.include?(child.extname.downcase) }

            names = files.map { |file| file.basename.to_s }.sort

            names.reject { |file| described.include?(file) || described.include?(Import.file_name(file)) }
          end

          def review_of(dir)
            sheet = Sheet.load(dir, raw: @raw)
            @memo.clear if @memo.size > MEMORISED
            errors, warnings = Review.new(sheet, memo: @memo).findings.partition { |finding| finding.level == :error }

            { errors: errors.map(&:message), warnings: warnings.map(&:message), unreadable: nil, sheet: sheet,
              proposal: sheet.tables.map { |table| "#{table.file} → #{table.name}" } }
          rescue Psych::Exception => e
            { errors: [], warnings: [], unreadable: e.message.lines.first.to_s.strip, sheet: nil, proposal: [] }
          end

          # @return [Hash, nil] number of lines and first lines of a table, when it reads. A large table is
          #   not read whole for that: its lines are counted as the file has them.
          def preview(file)
            return nil unless file.file?

            head = CSV.foreach(file, encoding: 'bom|utf-8').first(Pages::PREVIEWED + 1)
            return nil unless head.flatten.compact.all?(&:valid_encoding?)

            { rows: [file.each_line.count { |line| !line.strip.empty? } - 1, 0].max, head: head }
          rescue CSV::MalformedCSVError, ArgumentError
            nil
          end

          # @return [String] changes whenever a file of the dataset is added, removed or written
          def fingerprint(dir)
            files = dir.children.select(&:file?).sort
            # A table being read, then read or refused, changes the page as a file does
            reading = @imports[dir.basename.to_s].to_h.values_at(:file, :pending, :problem).join('|')

            Digest::SHA1.hexdigest([*files.map { |file| [file.basename, file.mtime.to_f, file.size].join('|') }, reading].join("\n"))
          end

          def html(body, status: 200)
            Response.new(status: status, headers: { 'Content-Type' => 'text/html; charset=utf-8' }, body: body)
          end

          def json(value)
            Response.new(status: 200, headers: { 'Content-Type' => 'application/json; charset=utf-8' }, body: JSON.generate(value))
          end

          def text(status, body)
            Response.new(status: status, headers: { 'Content-Type' => 'text/plain; charset=utf-8' }, body: body)
          end

          def redirect(location)
            Response.new(status: 303, headers: { 'Location' => location }, body: '')
          end
      end
    end
  end
end
