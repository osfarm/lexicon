# frozen_string_literal: true

require 'csv'
require 'date'
require 'tempfile'

module Lexicon
  module Contribution
    # Reads a table as a contributor has it — a CSV of any separator and encoding, an Excel or LibreOffice
    # sheet — and makes of it what a tabular contribution expects: column names without accent or space,
    # the type of each column, values written the way that type is read, the column that identifies a
    # line, and the columns that carry an identifier Lexicon knows. Everything it did is said in French.
    class Import
      # The file cannot be made a table: the message says why, for the contributor
      class Unreadable < StandardError; end

      Result = Struct.new(:file, :csv, :columns, :key, :pivots, :notes, keyword_init: true)

      SPREADSHEETS = %w[.xlsx .xlsm .xls .ods].freeze
      TEXTS = %w[.csv .tsv .txt].freeze
      EXTENSIONS = (TEXTS + SPREADSHEETS).freeze
      SEPARATORS = { ',' => 'la virgule', ';' => 'le point-virgule', "\t" => 'la tabulation', '|' => 'la barre verticale' }.freeze
      # Lines read to tell the separator
      SAMPLED = 30

      BOOLEANS = { 'true' => 'true', 'false' => 'false', 'oui' => 'true', 'non' => 'false', 'vrai' => 'true', 'faux' => 'false',
                   'yes' => 'true', 'no' => 'false' }.freeze
      INTEGER = /\A-?(0|[1-9]\d*)\z/.freeze
      NUMBER = /\A-?(0|[1-9]\d*)([.,]\d+)?\z/.freeze
      # Thousands separated by a space, as a spreadsheet shows them
      GROUPED = /\A-?[1-9]\d{0,2}([ \u00A0\u202F]\d{3})+(,\d+)?\z/.freeze
      ISO_DATE = /\A(\d{4})-(\d{2})-(\d{2})\z/.freeze
      FRENCH_DATE = %r{\A(\d{1,2})[/.-](\d{1,2})[/.-](\d{4})\z}.freeze
      # A day written as an instant, as open data portals export it: midnight, there or in universal time
      INSTANT = Sheet::INSTANT
      # A day and a time as a French spreadsheet shows them: 04/12/2025 17:00
      FRENCH_INSTANT = %r{\A(\d{1,2})[/.-](\d{1,2})[/.-](\d{4})[ T](\d{1,2})[:h](\d{2})(?::(\d{2}))?\z}.freeze
      # Renamed columns named one by one, before they are only counted
      NAMED = 3
      # A point as open data portals and tools write it: a pair, an object with lat and lon, or WKT
      PAIR = /\A(#{Sheet::COORDINATE})\s*[,; ]\s*(#{Sheet::COORDINATE})\z/.freeze
      OBJECT = /\A\{.*\}\z/m.freeze
      WKT = /\APOINT\s*\(\s*(#{Sheet::COORDINATE})\s+(#{Sheet::COORDINATE})\s*\)\z/i.freeze
      LOCATED = /geo|coord|lat_?lon|lon_?lat|position|point|gps|localisation/.freeze
      # Columns that hold a code, not a quantity, whatever their values look like
      CODE = /(?:\A|_)(id|code|codes|insee|siren|siret|postal|cp|amm|ref|reference|numero|num|telephone|tel)(?:_|\z)/.freeze
      IDENTIFIER = /(?:\A|_)(id|code|ref|reference|numero|identifiant)(?:_|\z)/.freeze
      # Share of the values of a column that must have the shape of a key: a source always holds a few that do not
      SHAPED = 0.95
      # Column name and shape of the values that tell a linking key
      PIVOTS = {
        'commune' => [/insee|commune|(?:\A|_)com_code(?:_|\z)|code_com(?:_|\z)|code_?geo/, /\A(\d{5}|2[AB]\d{3})\z/],
        'siren' => [/siren/, /\A\d{9}\z/],
        'siret' => [/siret/, /\A\d{14}\z/],
        'department' => [/depart|(?:\A|_)dep(?:_|\z)/, /\A(\d{2,3}|2[AB])\z/],
        'amm' => [/(?:\A|_)amm(?:_|\z)/, /\A\d{7}\z/]
      }.freeze

      # Names of the columns that tell a commune by its postal code and its name, when none carries its code
      POSTAL_CODE = /code_?postal|postal_?code|(?:\A|_)(cp|zip)(?:_|\z)/.freeze
      COMMUNE_NAME = /(?:\A|_)(com_name|nom_com|commune|communes|ville|localite|city|lib_com)(?:_|\z)|libelle_commune|nom_commune/.freeze

      # @param [String] name name of a file as the contributor has it
      # @return [String] name of the CSV file its import writes
      def self.file_name(name)
        "#{slug(File.basename(name.to_s, '.*'), 'tableau')}.csv"
      end

      # @return [String] in small letters, without accent or space
      def self.slug(text, default)
        plain = text.to_s.gsub('œ', 'oe').gsub('æ', 'ae').unicode_normalize(:nfd).gsub(/\p{Mn}/, '').downcase
        plain = plain.gsub(/[^a-z0-9]+/, '_').gsub(/\A_+|_+\z/, '')

        plain.empty? ? default : plain
      end

      # @param [String] name name of the file as the contributor has it
      # @param [String] content its bytes
      def initialize(name, content)
        @name = name.to_s
        @content = content.to_s
        @notes = []
      end

      # @return [Result]
      # @raise [Unreadable]
      def result
        headers, lines = table
        names = column_names(headers)
        types = names.each_with_index.map { |name, index| type_of(name, lines.map { |line| line[index] }) }
        lines = lines.map { |line| line.each_with_index.map { |value, index| written(value, types[index]) } }
        note_types(names, types)
        key, names, types, lines = identified(names, types, lines)
        pivots = pivots_of(names, lines)
        pivots = pivots.merge(place_of(names, types, lines)) unless pivots.value?('commune')
        pivots.each_key { |name| types[names.index(name)] = 'text' }

        Result.new(file: self.class.file_name(@name), csv: CSV.generate { |csv| [names, *lines].each { |line| csv << line } },
                   columns: names.zip(types).to_h, key: key, pivots: pivots, notes: @notes)
      end

      private

        # @return [Array] the titles, and the lines under them
        def table
          extension = File.extname(@name).downcase
          unless EXTENSIONS.include?(extension)
            raise Unreadable.new("« #{@name} » : ce format n'est pas lu. Formats lus : #{EXTENSIONS.join(', ')}.")
          end

          rows = SPREADSHEETS.include?(extension) ? spreadsheet_rows(extension) : text_rows(extension)
          rows = rows.map { |row| row.map { |cell| cell.to_s.strip } }.reject { |row| row.all?(&:empty?) }
          raise Unreadable.new("« #{@name} » est vide.") if rows.empty?
          raise Unreadable.new("« #{@name} » n'a que sa ligne de titres.") if rows.size == 1

          width = rows.map { |row| row.rindex { |cell| !cell.empty? }.to_i + 1 }.max
          rows = rows.map { |row| Array.new(width) { |index| row[index].to_s } }
          [rows.first, rows.drop(1)]
        end

        def text_rows(extension)
          text = utf8(@content)
          separator = extension == '.tsv' ? "\t" : separator_of(text)
          @notes << "Le séparateur du fichier est #{SEPARATORS[separator]} : il est remplacé par la virgule." unless separator == ','

          CSV.parse(text, col_sep: separator, liberal_parsing: true)
        rescue CSV::MalformedCSVError
          raise Unreadable.new("« #{@name} » ne se lit pas comme un tableau : l'enregistrer de nouveau en CSV depuis le tableur.")
        end

        def utf8(content)
          text = content.dup.force_encoding(Encoding::UTF_8).delete_prefix("\uFEFF")
          return text if text.valid_encoding?

          @notes << "Le fichier n'était pas en UTF-8 : il est converti, les accents sont gardés."
          content.dup.force_encoding(Encoding::WINDOWS_1252).encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
        end

        # The separator that cuts the first lines into the same number of columns, more than one
        def separator_of(text)
          sample = text.lines.first(SAMPLED).join
          scores = SEPARATORS.keys.map do |separator|
            widths = CSV.parse(sample, col_sep: separator, liberal_parsing: true).reject(&:empty?).map(&:size)
            [separator, widths.uniq.size == 1 && widths.first > 1 ? widths.first : 0]
          rescue CSV::MalformedCSVError
            [separator, 0]
          end
          best = scores.max_by { |_, score| score }

          best.last.zero? ? ',' : best.first
        end

        def spreadsheet_rows(extension)
          Tempfile.create(['import', extension], binmode: true) do |file|
            file.write(@content)
            file.flush
            book = ::Roo::Spreadsheet.open(file.path, extension: extension.delete('.').to_sym)
            sheet = book.sheet(book.sheets.first)
            more = book.sheets.size > 1 ? " ; ses #{book.sheets.size - 1} autres feuilles sont laissées" : ''
            @notes << "La première feuille du classeur, « #{book.sheets.first} », est lue#{more}."

            sheet.first_row.nil? ? [] : (sheet.first_row..sheet.last_row).map { |index| sheet.row(index).map { |cell| cell_text(cell) } }
          end
        rescue Unreadable
          raise
        rescue StandardError
          raise Unreadable.new("« #{@name} » ne s'ouvre pas comme un classeur : l'enregistrer de nouveau depuis le tableur.")
        end

        # What a cell of a spreadsheet holds, written as a CSV would
        def cell_text(cell)
          case cell
          when DateTime, Time then cell.strftime(cell.hour.zero? && cell.min.zero? ? '%Y-%m-%d' : '%Y-%m-%d %H:%M')
          when Date then cell.iso8601
          when Float then cell == cell.to_i ? cell.to_i.to_s : cell.to_s
          when true, false then cell.to_s
          else cell.to_s
          end
        end

        def column_names(headers)
          taken = Hash.new(0)
          names = headers.each_with_index.map do |header, index|
            name = slug(header, "colonne_#{index + 1}")
            name = "c_#{name}" unless name.match?(/\A[a-z]/)
            taken[name] += 1
            taken[name] > 1 ? "#{name}_#{taken[name]}" : name
          end
          note_names(headers.zip(names).reject { |header, name| header == name })

          names
        end

        def note_names(renamed)
          if renamed.size <= NAMED
            renamed.each { |header, name| @notes << "La colonne « #{header} » s'appelle maintenant « #{name} »." }
          else
            examples = renamed.first(NAMED).map { |header, name| "« #{header} » devient « #{name} »" }.join(', ')
            @notes << "#{renamed.size} colonnes sont renommées en minuscules, sans accent ni espace : #{examples}…"
          end
        end

        def slug(text, default)
          self.class.slug(text, default)
        end

        def type_of(name, values)
          filled = values.reject(&:empty?)
          return 'text' if filled.empty?
          return 'boolean' if filled.all? { |value| BOOLEANS.key?(value.downcase) }
          return 'date' if filled.all? { |value| date_of(value) }
          return 'datetime' if filled.all? { |value| instant_of(value) }
          return 'point' if filled.all? { |value| point_of(value, name) }
          return 'text' if name.match?(CODE)
          return 'integer' if filled.all? { |value| value.match?(INTEGER) }

          filled.all? { |value| value.match?(NUMBER) || value.match?(GROUPED) } ? 'number' : 'text'
        end

        # @return [Array<String>, nil] latitude and longitude as written. Two whole numbers side by side are only
        #   a point when the name of the column says so.
        def point_of(value, name)
          pair = if (plain = value.match(PAIR))
                   plain.captures if name.match?(LOCATED) || plain.captures.all? { |part| part.include?('.') }
                 elsif (wkt = value.match(WKT))
                   wkt.captures.reverse
                 elsif value.match?(OBJECT)
                   %w[lat lon].map { |key| value[/["']?#{key}(?:itude|gitude)?["']?\s*[:=]>?\s*["']?(#{Sheet::COORDINATE})/i, 1] }
                 end

          pair && pair.none?(&:nil?) && Sheet.point(pair.join(',')) ? pair : nil
        end

        # @return [String, nil] a day and a time the way they are read; a day alone is the start of that day
        def instant_of(value)
          written = if value.match?(INSTANT)
                      value.sub(' ', 'T')
                    elsif (french = value.match(FRENCH_INSTANT))
                      day, month, year, hours, minutes, seconds = french.captures
                      format('%<year>s-%<month>02d-%<day>02dT%<hours>02d:%<minutes>s:%<seconds>s',
                             year: year, month: month.to_i, day: day.to_i, hours: hours.to_i, minutes: minutes, seconds: seconds || '00')
                    elsif (date = date_of(value))
                      "#{date.iso8601}T00:00:00"
                    end

          written && Sheet.instant?(written) ? written : nil
        end

        # @return [Date, nil]
        def date_of(value)
          year, month, day = if (iso = value.match(ISO_DATE))
                               iso.captures
                             elsif (french = value.match(FRENCH_DATE))
                               french.captures.reverse
                             elsif (instant = value.match(INSTANT)) && midnight?(instant)
                               instant.captures.first(3)
                             end

          year && Date.valid_date?(year.to_i, month.to_i, day.to_i) ? Date.new(year.to_i, month.to_i, day.to_i) : nil
        end

        # An instant only stands for a day when it carries no time of its own
        def midnight?(instant)
          hours, minutes, seconds, zone = instant.captures.drop(3)
          return false unless seconds.to_i.zero?

          shift = zone.to_s.match(/([+-])(\d{2}):?(\d{2})/)
          offset = shift ? "#{shift[1]}1".to_i * (shift[2].to_i * 60 + shift[3].to_i) : 0
          local = hours.to_i * 60 + minutes.to_i

          local.zero? || ((local - offset) % 1440).zero?
        end

        # @return [String] the value, written the way its type is read
        def written(value, type)
          return value if value.empty?

          case type
          when 'boolean' then BOOLEANS.fetch(value.downcase)
          when 'date' then date_of(value).iso8601
          when 'datetime' then instant_of(value)
          when 'point' then point_of(value, 'point').join(',')
          when 'number', 'integer' then value.gsub(/[ \u00A0\u202F]/, '').tr(',', '.')
          else value
          end
        end

        def note_types(names, types)
          said = { 'date' => 'des dates, écrites AAAA-MM-JJ', 'number' => 'des nombres, écrits avec un point pour les décimales',
                   'integer' => 'des nombres entiers', 'boolean' => 'des oui/non, écrits true ou false',
                   'datetime' => 'des dates avec leur heure, écrites AAAA-MM-JJTHH:MM:SS',
                   'point' => 'des points géographiques, écrits latitude,longitude' }

          names.zip(types).each { |name, type| @notes << "« #{name} » : #{said[type]}." if said.key?(type) }
        end

        # The column that identifies each line; one is added when no column does
        def identified(names, types, lines)
          candidates = names.each_index.select do |index|
            values = lines.map { |line| line[index] }
            values.none?(&:empty?) && values.uniq.size == values.size
          end
          chosen = candidates.find { |index| names[index] == 'id' } || candidates.find { |index| names[index].match?(IDENTIFIER) } ||
                   candidates.find { |index| types[index] == 'text' }
          if chosen
            @notes << "« #{names[chosen]} » identifie chaque ligne : aucune valeur vide, aucune en double."
            return [names[chosen], names, types, lines]
          end

          added = names.include?('id') ? 'ligne' : 'id'
          @notes << "Aucune colonne n'identifie chaque ligne : une colonne « #{added} » est ajoutée, qui les numérote."
          [added, [added, *names], ['integer', *types], lines.each_with_index.map { |line, index| [(index + 1).to_s, *line] }]
        end

        # @return [Hash{String => String}] columns that carry an identifier shared with other datasets
        def pivots_of(names, lines)
          names.each_with_index.each_with_object({}) do |(name, index), pivots|
            filled = lines.map { |line| line[index] }.reject(&:empty?)
            key, = PIVOTS.find do |_, (named, shaped)|
              name.match?(named) && filled.any? && filled.count { |value| value.match?(shaped) } >= SHAPED * filled.size
            end
            next if key.nil? || pivots.value?(key)

            pivots[name] = key
            @notes << "« #{name} » est reconnue comme un lien : #{key}."
          end
        end

        # Without a column of INSEE codes, the postal code and the name of the commune tell it together
        def place_of(names, types, lines)
          postal = names.each_index.find do |index|
            filled = lines.map { |line| line[index] }.reject(&:empty?)
            names[index].match?(POSTAL_CODE) && filled.any? && filled.all? { |value| value.match?(/\A\d{5}\z/) }
          end
          named = names.each_index.find { |index| index != postal && types[index] == 'text' && names[index].match?(COMMUNE_NAME) }
          return {} if postal.nil? || named.nil?

          @notes << "« #{names[postal]} » et « #{names[named]} » désignent ensemble une commune : le Lexicon en trouvera le code INSEE."
          { names[postal] => 'commune_postal_code', names[named] => 'commune_name' }
        end
    end
  end
end
