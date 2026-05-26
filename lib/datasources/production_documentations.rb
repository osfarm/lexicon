require 'csv'
require 'fileutils'
require 'net/http'
require 'nokogiri'
require 'uri'

module Datasources
  class ProductionDocumentations < Base
    description 'Liens entre les productions Ekylibre et la documentation Triple Performance'
    credits name: 'Triple Performance',
            url: 'https://wiki.tripleperformance.fr/wiki/Productions',
            provider: 'Triple Performance (collectif)',
            licence: 'CC-BY-SA 4.0',
            licence_url: 'https://creativecommons.org/licenses/by-sa/4.0/deed.fr',
            updated_at: '2026-05-22'

    SOURCE_KEY = 'tripleperformance'.freeze
    WIKI_HOST  = 'https://wiki.tripleperformance.fr'.freeze
    ROOT_PATH  = '/wiki/Productions'.freeze

    OVERRIDES_SRC  = 'data/production_documentations/overrides.csv'.freeze
    WIKI_LINKS_CSV = 'wiki_links.csv'.freeze
    OVERRIDES_CSV  = 'overrides.csv'.freeze

    # Cartes "catégorie thématique" (page d'accueil Productions ET pages de
    # catégories qui ne déclinent pas leurs productions en cartes-vignettes —
    # Élevage, Viticulture, Cultures tropicales).
    SELECTOR_THEMATIQUE = 'div.thematique a.stretched-link'.freeze
    # Cartes "production individuelle" (Grandes cultures, Arboriculture,
    # Maraîchage). Une `very-small-card` contient l'image + le lien titré.
    SELECTOR_CARD = 'div.very-small-card a[href][title]'.freeze

    def collect
      FileUtils.mkdir_p(dir)

      # Passe 1 : page d'accueil → 9 catégories.
      categories = extract_links_by(SELECTOR_THEMATIQUE, fetch_page(ROOT_PATH))
      raise "Aucune catégorie détectée sur #{ROOT_PATH} — sélecteur invalide ?" if categories.empty?
      logger.debug "#{categories.size} catégorie(s) détectée(s)"

      # Passe 2 : pour chaque catégorie, on union les deux patterns.
      rows = []
      categories.each do |cat|
        doc = fetch_page(cat[:url_path])
        sub_links = (extract_links_by(SELECTOR_THEMATIQUE, doc) +
                     extract_links_by(SELECTOR_CARD, doc)).uniq { |h| h[:url_path] }
        logger.debug "  #{cat[:label]} : #{sub_links.size} lien(s)"
        sub_links.each do |link|
          rows << [cat[:label], link[:label], link[:url_path], absolute_url(link[:url_path])]
        end
        sleep 0.2 # politesse réseau
      end

      CSV.open(dir.join(WIKI_LINKS_CSV), 'w', write_headers: true,
                                              headers: %w[category fr_label url_path url]) do |out|
        rows.uniq { |r| [r[0], r[3]] }.each { |r| out << r }
      end
      logger.debug "Écrit #{rows.size} lien(s) dans #{WIKI_LINKS_CSV}"

      # Snapshot du CSV d'overrides statique → raw/ pour load_csv.
      raise "Fichier d'overrides absent : #{OVERRIDES_SRC}" unless File.exist?(OVERRIDES_SRC)
      FileUtils.cp(OVERRIDES_SRC, dir.join(OVERRIDES_CSV))
    end

    def load
      load_csv(dir.join(WIKI_LINKS_CSV), 'wiki_links')
      load_csv(dir.join(OVERRIDES_CSV),  'overrides')
    end

    def self.table_definitions(builder)
      builder.table :master_production_documentations, sql: <<-SQL
        CREATE TABLE master_production_documentations (
          production_reference_name character varying NOT NULL,
          source                    character varying NOT NULL,
          url                       character varying NOT NULL,
          PRIMARY KEY (production_reference_name, source)
        );
        CREATE INDEX master_production_documentations_source
          ON master_production_documentations(source);
      SQL
    end

    def normalize
      # 1) Overrides manuels — autorité finale (UPSERT).
      query <<~SQL
        INSERT INTO master_production_documentations (production_reference_name, source, url)
          SELECT production_reference_name, source, url
            FROM production_documentations.overrides
           WHERE production_reference_name IS NOT NULL AND production_reference_name <> ''
             AND source IS NOT NULL AND source <> ''
             AND url IS NOT NULL AND url <> ''
          ON CONFLICT (production_reference_name, source) DO UPDATE SET url = EXCLUDED.url
      SQL

      # 2) Auto-match exact (normalisé). N'écrase pas les overrides.
      query <<~SQL
        INSERT INTO master_production_documentations (production_reference_name, source, url)
          SELECT mp.reference_name, '#{SOURCE_KEY}', wl.url
            FROM master_productions mp
            JOIN master_translations mt ON mt.id = mp.translation_id
            JOIN production_documentations.wiki_links wl
              ON LOWER(TRANSLATE(mt.fra, '’', '''')) = LOWER(TRANSLATE(wl.fr_label, '’', ''''))
          ON CONFLICT (production_reference_name, source) DO NOTHING
      SQL

      # 3) Auto-match par préfixe : la page wiki couvre la culture générique
      # ("Blé tendre" / "Pomme de terre"), et le master_productions a une
      # variante plus spécifique ("Blé tendre d'hiver", "Pomme de terre
      # féculière"). Pour éviter qu'un label trop court ne rafle un nom plus
      # spécifique d'une autre culture (ex. "Pomme" qui matcherait "Pomme de
      # terre féculière"), on choisit pour chaque production le wiki label le
      # PLUS LONG qui en est un préfixe — via DISTINCT ON length DESC.
      query <<~SQL
        INSERT INTO master_production_documentations (production_reference_name, source, url)
          SELECT DISTINCT ON (mp.reference_name)
                 mp.reference_name, '#{SOURCE_KEY}', wl.url
            FROM master_productions mp
            JOIN master_translations mt ON mt.id = mp.translation_id
            JOIN production_documentations.wiki_links wl
              ON LOWER(TRANSLATE(mt.fra, '’', '''')) LIKE
                 LOWER(TRANSLATE(wl.fr_label, '’', '''')) || ' %'
           ORDER BY mp.reference_name, length(wl.fr_label) DESC
          ON CONFLICT (production_reference_name, source) DO NOTHING
      SQL
    end

    private

      def fetch_page(path)
        uri = URI.parse(absolute_url(path))
        req = Net::HTTP::Get.new(uri)
        req['User-Agent'] = 'lexicon-production-documentations'
        res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |h| h.request(req) }
        unless res.is_a?(Net::HTTPSuccess)
          raise "GET #{uri} returned #{res.code}: #{res.body.to_s[0, 200]}"
        end
        Nokogiri::HTML(res.body)
      end

      def extract_links_by(selector, doc)
        doc.css(selector).filter_map do |a|
          href = a['href'].to_s
          next unless href.start_with?('/wiki/')
          # Strip section ancres (#...) et namespaces (Spécial:, Catégorie:, etc.)
          href = href.split('#').first
          next if excluded_namespace?(href)
          next if a['class'].to_s.split.include?('new') # red links

          # Pour les vignettes (.very-small-card), le texte d'ancrage est une
          # image — on prend `title=` (toujours présent par construction du wiki).
          # Pour les cartes thématiques, le `title` est aussi présent et égal au
          # texte. Donc `title || text` est robuste.
          label = (a['title'] || a.text).to_s.strip
          next if label.empty?

          { label: label, url_path: href }
        end
      end

      def excluded_namespace?(href)
        EXCLUDED_NAMESPACES.any? { |ns| href.start_with?("/wiki/#{ns}") }
      end

      def absolute_url(path)
        "#{WIKI_HOST}#{path}"
      end

      # Préfixes URL-encodés ET en clair (Nokogiri renvoie tantôt l'un, tantôt l'autre
      # selon que le HTML a été produit par MediaWiki avec ou sans encodage).
      EXCLUDED_NAMESPACES = %w[
        Cat%C3%A9gorie: Sp%C3%A9cial: Fichier: Aide: Discussion: Mod%C3%A8le:
        Catégorie: Spécial: Fichier: Aide: Discussion: Modèle:
        Category: Special: File: Help: Talk: Template:
      ].freeze
  end
end
