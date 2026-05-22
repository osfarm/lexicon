require 'json'
require 'net/http'
require 'uri'
require 'fileutils'

module Datasources
  class AgriculturalPictures < Base
    description "Pictures et icônes utilisées par Ekylibre (variétés, familles d'activité, pays)"
    credits name: 'Ekylibre assets',
            url: 'https://github.com/ekylibre/ekylibre',
            provider: 'Ekylibre SAS',
            licence: 'AGPL-3.0',
            licence_url: 'https://www.gnu.org/licenses/agpl-3.0.html',
            updated_at: '2026-05-22'

    GITHUB_REPO   = 'ekylibre/ekylibre'.freeze
    GITHUB_BRANCH = 'main'.freeze

    DOMAINS = {
      'varieties'         => 'app/assets/images/varieties',
      'activity_families' => 'app/assets/images/activity_families',
      'countries'         => 'app/assets/images/countries',
    }.freeze

    def collect
      DOMAINS.each do |domain, path|
        target_dir = dir.join(domain)
        FileUtils.mkdir_p(target_dir)
        entries = list_github_contents(path)
        files = entries.select { |e| e['type'] == 'file' && !e['download_url'].to_s.empty? }
        logger.debug "domain=#{domain} : #{files.size} fichier(s) à récupérer"
        files.each do |entry|
          downloader.curl(entry['download_url'], out: "#{domain}/#{entry['name']}")
        end
      end
    end

    def load
      # Pas de chargement direct : les fichiers sont copiés dans la base via COPY, ce qui est plus rapide que les insertions ligne à ligne.
    end

    def self.table_definitions(builder)
      builder.table :master_agricultural_pictures, sql: <<-SQL
        CREATE TABLE master_agricultural_pictures (
          id        SERIAL PRIMARY KEY NOT NULL,
          domain    character varying NOT NULL,
          name      character varying NOT NULL,
          extension character varying NOT NULL,
          picture   BYTEA NOT NULL,
          UNIQUE (domain, name, extension)
        );
        CREATE INDEX master_agricultural_pictures_id ON master_agricultural_pictures(id);
        CREATE INDEX master_agricultural_pictures_domain ON master_agricultural_pictures(domain);
        CREATE INDEX master_agricultural_pictures_domain_name ON master_agricultural_pictures(domain, name);
      SQL
    end

    def normalize
      database.copy_data 'COPY master_agricultural_pictures (domain, name, extension, picture) FROM STDIN' do |c|
        DOMAINS.each_key do |domain|
          Dir.glob(dir.join(domain, '*')).sort.each do |file|
            next unless File.file?(file)

            basename  = File.basename(file)
            name      = File.basename(basename, '.*')
            extension = File.extname(basename).delete_prefix('.')
            hex       = File.binread(file).unpack1('H*')
            # COPY TEXT : "\x<hex>" est l'encodage bytea hex ; le backslash est doublé
            # pour traverser l'échappement COPY (sur le wire : \\x<hex>).
            c.call "#{escape_copy(domain)}\t#{escape_copy(name)}\t#{escape_copy(extension)}\t\\\\x#{hex}\n"
          end
        end
      end
    end

    private

      def list_github_contents(path)
        url = URI.parse("https://api.github.com/repos/#{GITHUB_REPO}/contents/#{path}?ref=#{GITHUB_BRANCH}")
        req = Net::HTTP::Get.new(url)
        req['Accept']     = 'application/vnd.github+json'
        req['User-Agent'] = 'lexicon-agricultural-pictures'
        token = ENV['GITHUB_TOKEN'].to_s
        req['Authorization'] = "Bearer #{token}" unless token.empty?

        res = Net::HTTP.start(url.host, url.port, use_ssl: true) { |http| http.request(req) }
        unless res.is_a?(Net::HTTPSuccess)
          raise "GitHub API #{url} returned #{res.code}: #{res.body.to_s[0, 200]}"
        end

        payload = JSON.parse(res.body)
        unless payload.is_a?(Array)
          raise "Unexpected GitHub API payload for #{path}: #{payload.class} (expected Array)"
        end
        payload
      end

      # Protège les caractères spéciaux du format COPY TEXT. Bloc explicite (plutôt
      # qu'un replacement String avec backslashes empilés) car le replacement String
      # de gsub réinterprète "\\" comme un seul backslash — illisible pour ce cas.
      COPY_ESCAPES = { '\\' => '\\\\', "\t" => '\\t', "\n" => '\\n', "\r" => '\\r' }.freeze

      def escape_copy(str)
        str.to_s.gsub(/[\\\t\n\r]/) { |c| COPY_ESCAPES[c] }
      end
  end
end
