require 'csv'
require 'set'

module Datasources
  # Documents de la plateforme R&D agricole (rd-agri.fr) et leurs liens aux
  # référentiels Lexicon : productions, taxons, zones administratives,
  # systèmes de production, ravageurs et maladies.
  #
  # L'export CSV « Documents » est déposé à la main dans raw/rd_agri/ (voir
  # doc/datasources/rd_agri.md). Conception : claudedocs/design_rd_agri.md.
  class RdAgri < Base
    description 'Documents de la plateforme R&D agricole et leurs liens aux référentiels Lexicon'
    credits name: 'Plateforme R&D Agricole',
            url: 'https://rd-agri.fr',
            provider: 'rd-agri (ACTA)',
            licence: 'CC BY-NC-SA 4.0',
            licence_url: 'https://creativecommons.org/licenses/by-nc-sa/4.0/deed.fr',
            updated_at: '2026-09-15'
    depends_on :industry_sector, :open_nomenclature, :administrative_areas, :phytosanitary

    # Colonnes de l'export rd-agri → colonnes de documents.csv.
    # « Auteurs » n'y figure pas : la donnée nominative n'entre pas en base.
    EXPORT_COLUMNS = {
      'Titre' => 'title',
      'Année de publication' => 'publication_year',
      'Description' => 'description',
      'Mots-clés' => 'keywords',
      'URL de la notice' => 'notice_url',
      'Code projet' => 'project_code',
      'Nom du projet' => 'project_name',
      'Organisme(s)' => 'organisms',
      'Publicateur' => 'publisher',
      'Date de création' => 'created_on',
      'Date de publication' => 'published_on',
      'Langue' => 'language',
      "Labels tirés de l'enrichissement" => 'labels',
      'URL de la page' => 'page_url',
      'URL du document' => 'document_url'
    }.freeze

    DOCUMENTS_FILE = 'documents.csv'.freeze
    DATA_FILES = %w[keyword_mappings publishers languages giee_regions pest_exclusions
                    area_exclusions taxon_expansion_exclusions overrides].freeze
    FARMING_FAMILIES = %w[plant_farming animal_farming vine_farming].freeze
    TAXON_RANKS = %w[genus specie subspecie variety].freeze
    MAX_GRAM = 6
    MONTHS = %w[janvier février mars avril mai juin juillet août septembre octobre novembre décembre].freeze

    def collect
      FileUtils.mkdir_p(dir)
      source = find_export
      write_documents(source)
      DATA_FILES.each { |f| FileUtils.cp("data/rd_agri/#{f}.csv", dir) }
    end

    def load
      load_csv(dir.join(DOCUMENTS_FILE), 'documents', encoding: 'UTF-8')
      DATA_FILES.each { |f| load_csv(dir.join("#{f}.csv"), f, encoding: 'UTF-8') }
    end

    def self.table_definitions(builder)
      builder.table(:registered_rd_agri_documents, sql: <<~SQL)
        CREATE TABLE registered_rd_agri_documents (
          id character varying PRIMARY KEY NOT NULL,
          title character varying NOT NULL,
          description text,
          publication_year integer,
          published_on date,
          created_on date,
          publisher character varying,
          publisher_label character varying,
          language character varying,
          keywords text[] NOT NULL DEFAULT '{}',
          project_code character varying,
          project_name character varying,
          page_url character varying NOT NULL,
          notice_url character varying,
          document_url character varying,
          exported_on date NOT NULL
        );

        CREATE INDEX registered_rd_agri_documents_project_code ON registered_rd_agri_documents(project_code);
        CREATE INDEX registered_rd_agri_documents_publication_year ON registered_rd_agri_documents(publication_year);
      SQL

      builder.table(:registered_rd_agri_document_productions, sql: <<~SQL).references(document_id: [:registered_rd_agri_documents, :id], production: [:master_productions, :reference_name])
        CREATE TABLE registered_rd_agri_document_productions (
          document_id character varying NOT NULL,
          production character varying NOT NULL,
          channels text[] NOT NULL,
          PRIMARY KEY (document_id, production)
        );

        CREATE INDEX registered_rd_agri_document_productions_production ON registered_rd_agri_document_productions(production);
      SQL

      builder.table(:registered_rd_agri_document_taxa, sql: <<~SQL).references(document_id: [:registered_rd_agri_documents, :id], taxon: [:master_taxonomy, :reference_name])
        CREATE TABLE registered_rd_agri_document_taxa (
          document_id character varying NOT NULL,
          taxon character varying NOT NULL,
          channels text[] NOT NULL,
          PRIMARY KEY (document_id, taxon)
        );

        CREATE INDEX registered_rd_agri_document_taxa_taxon ON registered_rd_agri_document_taxa(taxon);
      SQL

      builder.table(:registered_rd_agri_document_areas, sql: <<~SQL).references(document_id: [:registered_rd_agri_documents, :id])
        CREATE TABLE registered_rd_agri_document_areas (
          document_id character varying NOT NULL,
          area_kind character varying NOT NULL,
          area_code character varying NOT NULL,
          channels text[] NOT NULL,
          PRIMARY KEY (document_id, area_kind, area_code)
        );

        CREATE INDEX registered_rd_agri_document_areas_area ON registered_rd_agri_document_areas(area_kind, area_code);
      SQL

      builder.table(:registered_rd_agri_document_production_systems, sql: <<~SQL).references(document_id: [:registered_rd_agri_documents, :id])
        CREATE TABLE registered_rd_agri_document_production_systems (
          document_id character varying NOT NULL,
          production_system character varying NOT NULL,
          channels text[] NOT NULL,
          PRIMARY KEY (document_id, production_system)
        );

        CREATE INDEX registered_rd_agri_document_production_systems_system ON registered_rd_agri_document_production_systems(production_system);
      SQL

      builder.table(:registered_rd_agri_document_pests, sql: <<~SQL).references(document_id: [:registered_rd_agri_documents, :id])
        CREATE TABLE registered_rd_agri_document_pests (
          document_id character varying NOT NULL,
          pest_source character varying NOT NULL CHECK (pest_source IN ('ephy_target', 'issue_nature')),
          pest_reference character varying NOT NULL,
          label character varying NOT NULL,
          channels text[] NOT NULL,
          PRIMARY KEY (document_id, pest_source, pest_reference)
        );

        CREATE INDEX registered_rd_agri_document_pests_reference ON registered_rd_agri_document_pests(pest_source, pest_reference);
      SQL
    end

    def normalize
      check_prerequisites
      create_helpers
      check_mappings
      insert_documents
      build_vocabularies
      build_tokens
      build_title_hits
      insert_productions
      insert_taxa
      insert_areas
      insert_production_systems
      insert_pests
      apply_overrides
      check_integrity
      report
    end

    private

      # --- collect ----------------------------------------------------------

      def find_export
        generated = [DOCUMENTS_FILE, *DATA_FILES.map { |f| "#{f}.csv" }]
        candidates = Dir.glob(dir.join('*.csv').to_s)
                        .reject { |f| generated.include?(File.basename(f)) }
                        .select { |f| documents_export?(f) }
                        .sort_by { |f| File.mtime(f) }

        if candidates.empty?
          raise "#{name} : aucun export « Documents » de rd-agri.fr dans #{dir}. " \
                'Procédure : doc/datasources/rd_agri.md'
        end

        candidates[0..-2].each { |f| logger.warn "#{name} : export ignoré (plus ancien) : #{File.basename(f)}" }
        logger.debug "#{name} : export retenu : #{File.basename(candidates.last)}"
        candidates.last
      end

      def documents_export?(file)
        header = File.open(file, 'r:bom|utf-8') { |io| CSV.parse_line(io.gets.to_s, col_sep: ';') }
        return false unless header && (EXPORT_COLUMNS.keys + ['Type']).all? { |c| header.include?(c) }

        first = CSV.foreach(file, col_sep: ';', headers: true, encoding: 'bom|utf-8').first
        first && first['Type'] == 'Document'
      rescue CSV::MalformedCSVError, ArgumentError
        false
      end

      def write_documents(source)
        exported_on = File.mtime(source).to_date.iso8601
        ids = Set.new
        count = 0

        CSV.open(dir.join(DOCUMENTS_FILE), 'w', write_headers: true,
                                                headers: ['id', *EXPORT_COLUMNS.values, 'exported_on']) do |out|
          CSV.foreach(source, col_sep: ';', headers: true, encoding: 'bom|utf-8') do |row|
            next unless row['Type'] == 'Document'

            id = row['URL de la page'].to_s.split('/').last
            raise "#{name} : document sans URL de page (ligne #{count + 2})" if id.blank?
            raise "#{name} : identifiant dupliqué #{id}" unless ids.add?(id)

            out << [id, *EXPORT_COLUMNS.keys.map { |k| row[k] }, exported_on]
            count += 1
          end
        end

        raise "#{name} : aucun document dans #{File.basename(source)}" if count.zero?

        logger.debug "#{name} : #{count} documents écrits dans #{DOCUMENTS_FILE} (export du #{exported_on})"
      end

      # --- normalize --------------------------------------------------------

      def check_prerequisites
        {
          'master_productions' => 'SELECT count(*) FROM master_productions',
          'master_taxonomy' => 'SELECT count(*) FROM master_taxonomy',
          'master_industry_sector_productions' => 'SELECT count(*) FROM master_industry_sector_productions',
          'master_nomenclatures (production_systems)' => "SELECT count(*) FROM master_nomenclatures WHERE nomenclature = 'production_systems'",
          'master_nomenclatures (issue_natures)' => "SELECT count(*) FROM master_nomenclatures WHERE nomenclature = 'issue_natures'",
          'registered_administrative_areas' => 'SELECT count(*) FROM registered_administrative_areas',
          'registered_phytosanitary_usages' => 'SELECT count(*) FROM registered_phytosanitary_usages'
        }.each do |table, sql|
          next if query(sql).getvalue(0, 0).to_i.positive?

          raise "#{name} : #{table} est vide. Lancer d'abord : ./lexicon run taxonomy productions " \
                'open_nomenclature administrative_areas phytosanitary industry_sector'
        end
      end

      # norm() : casse ignorée, accents conservés, ponctuation → espace.
      # fr_date() : « 05 janvier 2026 » → date.
      def create_helpers
        months = MONTHS.each_with_index.map { |m, i| "('#{m}', #{i + 1})" }.join(', ')

        query <<~SQL
          CREATE OR REPLACE FUNCTION #{name}.norm(s text) RETURNS text
            LANGUAGE sql IMMUTABLE
            AS $$ SELECT btrim(regexp_replace(lower(coalesce(s, '')), '[^[:alnum:]]+', ' ', 'g')) $$;

          DROP TABLE IF EXISTS #{name}.months;
          CREATE TABLE #{name}.months (name text PRIMARY KEY, num integer NOT NULL);
          INSERT INTO #{name}.months VALUES #{months};

          CREATE OR REPLACE FUNCTION #{name}.fr_date(s text) RETURNS date
            LANGUAGE sql STABLE
            AS $$
              SELECT make_date(split_part(x.t, ' ', 3)::integer, m.num, split_part(x.t, ' ', 1)::integer)
                FROM (SELECT lower(btrim(s)) AS t) x
                JOIN #{name}.months m ON m.name = split_part(x.t, ' ', 2)
               WHERE x.t ~ '^[0-9]{1,2} [[:alpha:]]+ [0-9]{4}$'
            $$;
        SQL
      end

      def check_mappings
        checks = {
          'keyword_mappings : target_kind invalide' =>
            "SELECT keyword FROM #{name}.keyword_mappings WHERE target_kind NOT IN ('industry_sector', 'production', 'ignore')",
          'keyword_mappings : filière inconnue' =>
            "SELECT target FROM #{name}.keyword_mappings WHERE target_kind = 'industry_sector' AND target NOT IN (SELECT reference_name FROM master_industry_sectors)",
          'keyword_mappings : production inconnue' =>
            "SELECT target FROM #{name}.keyword_mappings WHERE target_kind = 'production' AND target NOT IN (SELECT reference_name FROM master_productions)",
          'giee_regions : région inconnue' =>
            "SELECT prefix FROM #{name}.giee_regions WHERE region_code NOT IN (SELECT code FROM registered_administrative_areas WHERE kind = 'region')",
          'taxon_expansion_exclusions : taxon inconnu' =>
            "SELECT taxon FROM #{name}.taxon_expansion_exclusions WHERE taxon NOT IN (SELECT reference_name FROM master_taxonomy)",
          'taxon_expansion_exclusions : production inconnue' =>
            "SELECT production FROM #{name}.taxon_expansion_exclusions WHERE production NOT IN (SELECT reference_name FROM master_productions)",
          'overrides : target_kind ou action invalide' =>
            "SELECT document_id FROM #{name}.overrides WHERE target_kind NOT IN ('production', 'taxon', 'area', 'production_system', 'pest') OR action NOT IN ('add', 'remove')"
        }
        checks.each do |label, sql|
          wrong = values(sql)
          raise "#{name} : #{label} : #{wrong.uniq.join(', ')}" if wrong.any?
        end
      end

      def insert_documents
        query <<~SQL
          INSERT INTO registered_rd_agri_documents (
            id, title, description, publication_year, published_on, created_on, publisher, publisher_label,
            language, keywords, project_code, project_name, page_url, notice_url, document_url, exported_on
          )
          SELECT d.id,
                 COALESCE(NULLIF(btrim(d.title), ''), NULLIF(btrim(d.project_name), ''), d.id),
                 NULLIF(btrim(regexp_replace(d.description, '<[^>]+>', '', 'g'), E' \\t\\r\\n'), ''),
                 CASE WHEN d.publication_year ~ '^[0-9]{4}$' AND d.publication_year <> '1900' THEN d.publication_year::integer END,
                 #{name}.fr_date(d.published_on),
                 #{name}.fr_date(d.created_on),
                 COALESCE(p.canonical, NULLIF(btrim(d.publisher), '')),
                 NULLIF(btrim(d.publisher), ''),
                 l.iso,
                 COALESCE((SELECT array_agg(DISTINCT btrim(k) ORDER BY btrim(k))
                             FROM regexp_split_to_table(d.keywords, '[,;]') k
                            WHERE btrim(k) <> ''), '{}'),
                 NULLIF(btrim(d.project_code), ''),
                 NULLIF(btrim(d.project_name), ''),
                 d.page_url,
                 NULLIF(btrim(d.notice_url), ''),
                 NULLIF(btrim(d.document_url), ''),
                 d.exported_on::date
            FROM #{name}.documents d
            LEFT JOIN (SELECT DISTINCT ON (#{name}.norm(raw)) #{name}.norm(raw) AS k, canonical
                         FROM #{name}.publishers) p ON p.k = #{name}.norm(d.publisher)
            LEFT JOIN (SELECT DISTINCT ON (#{name}.norm(raw)) #{name}.norm(raw) AS k, iso
                         FROM #{name}.languages) l ON l.k = #{name}.norm(d.language)
        SQL
      end

      # Vocabulaires normalisés. La colonne `grp` regroupe les vocabulaires qui
      # se disputent un même passage du titre (règle du libellé le plus long).
      def build_vocabularies
        families = FARMING_FAMILIES.map { |f| "'#{f}'" }.join(', ')
        ranks = TAXON_RANKS.map { |r| "'#{r}'" }.join(', ')

        query <<~SQL
          DROP TABLE IF EXISTS #{name}.voc_keyword;
          CREATE TABLE #{name}.voc_keyword AS
            SELECT DISTINCT #{name}.norm(keyword) AS term, target_kind, NULLIF(target, '') AS target
              FROM #{name}.keyword_mappings
             WHERE #{name}.norm(keyword) <> '';

          DROP TABLE IF EXISTS #{name}.voc_production;
          CREATE TABLE #{name}.voc_production AS
            SELECT DISTINCT #{name}.norm(t.fra) AS term, p.reference_name AS production
              FROM master_productions p
              JOIN master_translations t ON t.id = p.translation_id
             WHERE p.activity_family IN (#{families})
               AND length(#{name}.norm(t.fra)) >= 3;

          DROP TABLE IF EXISTS #{name}.voc_taxon;
          CREATE TABLE #{name}.voc_taxon AS
            SELECT DISTINCT #{name}.norm(t.fra) AS term, x.reference_name AS taxon
              FROM master_taxonomy x
              JOIN master_translations t ON t.id = x.translation_id
             WHERE x.taxonomic_rank IN (#{ranks})
               AND length(#{name}.norm(t.fra)) >= 4;

          DROP TABLE IF EXISTS #{name}.voc_system;
          CREATE TABLE #{name}.voc_system AS
            SELECT DISTINCT #{name}.norm(label->>'fra') AS term, name AS production_system
              FROM master_nomenclatures
             WHERE nomenclature = 'production_systems';

          DROP TABLE IF EXISTS #{name}.voc_pest;
          CREATE TABLE #{name}.voc_pest AS
            SELECT * FROM (
              SELECT DISTINCT #{name}.norm(target_name_label_fra) AS term, 'ephy_target'::varchar AS source,
                     target_name_label_fra AS reference, target_name_label_fra AS label
                FROM registered_phytosanitary_usages
               WHERE target_name_label_fra IS NOT NULL
                 AND target_name_label_fra !~ '[*.]'
              UNION
              SELECT #{name}.norm(label->>'fra'), 'issue_nature', name, label->>'fra'
                FROM master_nomenclatures
               WHERE nomenclature = 'issue_natures'
            ) v
             WHERE length(term) >= 4
               AND NOT EXISTS (SELECT 1 FROM #{name}.pest_exclusions e
                                WHERE #{name}.norm(e.term) IN (v.term, v.term || 's')
                                   OR #{name}.norm(e.term) || 's' = v.term);

          DROP TABLE IF EXISTS #{name}.voc_area;
          CREATE TABLE #{name}.voc_area AS
            SELECT DISTINCT #{name}.norm(name) AS term, kind AS area_kind, code AS area_code
              FROM registered_administrative_areas;

          DROP TABLE IF EXISTS #{name}.voc_all;
          CREATE TABLE #{name}.voc_all AS
            SELECT term FROM #{name}.voc_keyword
            UNION SELECT term FROM #{name}.voc_production
            UNION SELECT term FROM #{name}.voc_taxon
            UNION SELECT term FROM #{name}.voc_system
            UNION SELECT term FROM #{name}.voc_pest;
          CREATE UNIQUE INDEX ON #{name}.voc_all (term);

          -- Élargissement taxon → productions agricoles ayant au moins une filière (§3.7.4)
          DROP TABLE IF EXISTS #{name}.taxon_productions;
          CREATE TABLE #{name}.taxon_productions AS
            WITH RECURSIVE up(production, taxon, depth) AS (
              SELECT reference_name, specie, 0
                FROM master_productions
               WHERE specie IS NOT NULL AND activity_family IN (#{families})
              UNION ALL
              SELECT up.production, t.parent, up.depth + 1
                FROM up
                JOIN master_taxonomy t ON t.reference_name = up.taxon
               WHERE t.parent IS NOT NULL AND up.depth < 30
            )
            SELECT DISTINCT up.taxon, up.production
              FROM up
             WHERE EXISTS (SELECT 1 FROM master_industry_sector_productions m WHERE m.production = up.production)
               AND NOT EXISTS (SELECT 1 FROM #{name}.taxon_expansion_exclusions e
                                WHERE e.taxon = up.taxon AND e.production = up.production);

          -- Résolution d'un terme en productions, avec priorité keyword > production > taxon (§3.7.2)
          DROP TABLE IF EXISTS #{name}.term_productions;
          CREATE TABLE #{name}.term_productions AS
            SELECT k.term, m.production, 'keyword'::varchar AS via
              FROM #{name}.voc_keyword k
              JOIN master_industry_sector_productions m ON m.industry_sector = k.target
             WHERE k.target_kind = 'industry_sector'
            UNION
            SELECT k.term, k.target, 'keyword'
              FROM #{name}.voc_keyword k
             WHERE k.target_kind = 'production'
            UNION
            SELECT p.term, p.production, 'production'
              FROM #{name}.voc_production p
             WHERE p.term NOT IN (SELECT term FROM #{name}.voc_keyword)
            UNION
            SELECT x.term, tp.production, 'taxon'
              FROM #{name}.voc_taxon x
              JOIN #{name}.taxon_productions tp ON tp.taxon = x.taxon
             WHERE x.term NOT IN (SELECT term FROM #{name}.voc_keyword)
               AND x.term NOT IN (SELECT term FROM #{name}.voc_production);
          CREATE INDEX ON #{name}.term_productions (term);
        SQL
      end

      def build_tokens
        query <<~SQL
          DROP TABLE IF EXISTS #{name}.doc_text;
          CREATE TABLE #{name}.doc_text AS
            SELECT id,
                   #{name}.norm(title) AS title_n,
                   #{name}.norm(coalesce(title, '') || ' ' || coalesce(regexp_replace(description, '<[^>]+>', ' ', 'g'), '')) AS text_n
              FROM #{name}.documents;
          CREATE UNIQUE INDEX ON #{name}.doc_text (id);

          DROP TABLE IF EXISTS #{name}.doc_kw;
          CREATE TABLE #{name}.doc_kw AS
            SELECT DISTINCT d.id, #{name}.norm(k) AS term
              FROM #{name}.documents d,
                   regexp_split_to_table(d.keywords, '[,;]') k
             WHERE #{name}.norm(k) <> '';

          -- Labels bruts : seuls ceux présents dans un vocabulaire sont conservés
          DROP TABLE IF EXISTS #{name}.doc_label;
          CREATE TABLE #{name}.doc_label AS
            SELECT DISTINCT l.id, l.term
              FROM (SELECT d.id, #{name}.norm(x) AS term
                      FROM #{name}.documents d,
                           regexp_split_to_table(d.labels, ',') x) l
              JOIN #{name}.voc_all v ON v.term = l.term;

          -- Label confirmé : présent (pluriel toléré) dans le titre ou la description
          DROP TABLE IF EXISTS #{name}.doc_label_ok;
          CREATE TABLE #{name}.doc_label_ok AS
            SELECT l.id, l.term
              FROM #{name}.doc_label l
              JOIN #{name}.doc_text t ON t.id = l.id
             WHERE t.text_n ~ ('\\m' || l.term || 's?\\M');
        SQL
      end

      # N-grammes du titre (1 à MAX_GRAM mots) croisés avec les vocabulaires ;
      # au sein d'un même groupe, un hit couvert par un hit plus long est retiré.
      def build_title_hits
        query <<~SQL
          DROP TABLE IF EXISTS #{name}.title_voc;
          CREATE TABLE #{name}.title_voc AS
            SELECT DISTINCT form, term, grp FROM (
              SELECT term, 'production' AS grp FROM #{name}.voc_keyword
              UNION SELECT term, 'production' FROM #{name}.voc_production
              UNION SELECT term, 'production' FROM #{name}.voc_taxon
              UNION SELECT term, 'system' FROM #{name}.voc_system
              UNION SELECT term, 'pest' FROM #{name}.voc_pest
              UNION SELECT term, 'area' FROM #{name}.voc_area
            ) v,
            LATERAL (VALUES (v.term), (v.term || 's')) f(form);
          CREATE INDEX ON #{name}.title_voc (form);

          DROP TABLE IF EXISTS #{name}.title_hit;
          CREATE TABLE #{name}.title_hit AS
            SELECT DISTINCT g.id, g.pos, g.len, v.term, v.grp
              FROM (
                SELECT t.id, s.pos, n.len, array_to_string(t.words[s.pos:s.pos + n.len - 1], ' ') AS gram
                  FROM (SELECT id, string_to_array(title_n, ' ') AS words FROM #{name}.doc_text WHERE title_n <> '') t
                 CROSS JOIN LATERAL generate_series(1, cardinality(t.words)) s(pos)
                 CROSS JOIN LATERAL generate_series(1, LEAST(#{MAX_GRAM}, cardinality(t.words) - s.pos + 1)) n(len)
              ) g
              JOIN #{name}.title_voc v ON v.form = g.gram;

          DELETE FROM #{name}.title_hit h
           WHERE EXISTS (
             SELECT 1 FROM #{name}.title_hit o
              WHERE o.id = h.id AND o.grp = h.grp AND o.len > h.len
                AND o.pos <= h.pos AND o.pos + o.len >= h.pos + h.len
           );
        SQL
      end

      def insert_productions
        query <<~SQL
          INSERT INTO registered_rd_agri_document_productions (document_id, production, channels)
            SELECT document_id, production, array_agg(DISTINCT channel ORDER BY channel)
              FROM (
                SELECT k.id AS document_id, tp.production, 'keyword' AS channel
                  FROM #{name}.doc_kw k
                  JOIN #{name}.term_productions tp ON tp.term = k.term
                UNION ALL
                SELECT l.id, tp.production, 'label'
                  FROM #{name}.doc_label_ok l
                  JOIN #{name}.term_productions tp ON tp.term = l.term AND tp.via IN ('production', 'taxon')
                UNION ALL
                SELECT h.id, tp.production, 'title'
                  FROM #{name}.title_hit h
                  JOIN #{name}.term_productions tp ON tp.term = h.term
                 WHERE h.grp = 'production'
              ) links
             GROUP BY document_id, production
        SQL
      end

      def insert_taxa
        query <<~SQL
          INSERT INTO registered_rd_agri_document_taxa (document_id, taxon, channels)
            SELECT document_id, taxon, array_agg(DISTINCT channel ORDER BY channel)
              FROM (
                SELECT k.id AS document_id, x.taxon, 'keyword' AS channel
                  FROM #{name}.doc_kw k JOIN #{name}.voc_taxon x ON x.term = k.term
                UNION ALL
                SELECT l.id, x.taxon, 'label'
                  FROM #{name}.doc_label_ok l JOIN #{name}.voc_taxon x ON x.term = l.term
                UNION ALL
                SELECT h.id, x.taxon, 'title'
                  FROM #{name}.title_hit h JOIN #{name}.voc_taxon x ON x.term = h.term
                 WHERE h.grp = 'production'
              ) links
             GROUP BY document_id, taxon
        SQL
      end

      def insert_areas
        query <<~SQL
          DROP TABLE IF EXISTS #{name}.organism_hit;
          CREATE TABLE #{name}.organism_hit AS
            SELECT DISTINCT g.id, g.org, g.pos, g.len, v.area_kind, v.area_code
              FROM (
                SELECT o.id, o.org, s.pos, n.len, array_to_string(o.words[s.pos:s.pos + n.len - 1], ' ') AS gram
                  FROM (SELECT d.id, x.org, string_to_array(#{name}.norm(x.org), ' ') AS words
                          FROM #{name}.documents d,
                               regexp_split_to_table(d.organisms, '[,;]') WITH ORDINALITY x(org, ord)
                         WHERE #{name}.norm(x.org) <> '') o
                 CROSS JOIN LATERAL generate_series(1, cardinality(o.words)) s(pos)
                 CROSS JOIN LATERAL generate_series(1, LEAST(#{MAX_GRAM}, cardinality(o.words) - s.pos + 1)) n(len)
              ) g
              JOIN #{name}.voc_area v ON v.term = g.gram;

          DELETE FROM #{name}.organism_hit h
           WHERE EXISTS (
             SELECT 1 FROM #{name}.organism_hit o
              WHERE o.id = h.id AND o.org = h.org AND o.len > h.len
                AND o.pos <= h.pos AND o.pos + o.len >= h.pos + h.len
           );

          INSERT INTO registered_rd_agri_document_areas (document_id, area_kind, area_code, channels)
            SELECT document_id, area_kind, area_code, array_agg(DISTINCT channel ORDER BY channel)
              FROM (
                SELECT d.id AS document_id, 'region' AS area_kind, g.region_code AS area_code, 'project_code' AS channel
                  FROM #{name}.documents d
                  JOIN #{name}.giee_regions g ON g.prefix = substring(d.project_code FROM '^[0-9]{2}([A-Z]+)_')
                UNION ALL
                SELECT id, area_kind, area_code, 'organism'
                  FROM #{name}.organism_hit
                UNION ALL
                SELECT h.id, v.area_kind, v.area_code, 'title'
                  FROM #{name}.title_hit h
                  JOIN #{name}.voc_area v ON v.term = h.term
                 WHERE h.grp = 'area'
                   AND h.term NOT IN (SELECT #{name}.norm(term) FROM #{name}.area_exclusions)
              ) links
             GROUP BY document_id, area_kind, area_code
        SQL
      end

      def insert_production_systems
        query <<~SQL
          INSERT INTO registered_rd_agri_document_production_systems (document_id, production_system, channels)
            SELECT document_id, production_system, array_agg(DISTINCT channel ORDER BY channel)
              FROM (
                SELECT k.id AS document_id, v.production_system, 'keyword' AS channel
                  FROM #{name}.doc_kw k JOIN #{name}.voc_system v ON v.term = k.term
                UNION ALL
                SELECT l.id, v.production_system, 'label'
                  FROM #{name}.doc_label_ok l JOIN #{name}.voc_system v ON v.term = l.term
                UNION ALL
                SELECT h.id, v.production_system, 'title'
                  FROM #{name}.title_hit h JOIN #{name}.voc_system v ON v.term = h.term
                 WHERE h.grp = 'system'
              ) links
             GROUP BY document_id, production_system
        SQL
      end

      def insert_pests
        query <<~SQL
          INSERT INTO registered_rd_agri_document_pests (document_id, pest_source, pest_reference, label, channels)
            SELECT document_id, source, reference, min(label), array_agg(DISTINCT channel ORDER BY channel)
              FROM (
                SELECT k.id AS document_id, v.source, v.reference, v.label, 'keyword' AS channel
                  FROM #{name}.doc_kw k JOIN #{name}.voc_pest v ON v.term = k.term
                UNION ALL
                SELECT l.id, v.source, v.reference, v.label, 'label'
                  FROM #{name}.doc_label_ok l JOIN #{name}.voc_pest v ON v.term = l.term
                UNION ALL
                SELECT h.id, v.source, v.reference, v.label, 'title'
                  FROM #{name}.title_hit h JOIN #{name}.voc_pest v ON v.term = h.term
                 WHERE h.grp = 'pest'
              ) links
             GROUP BY document_id, source, reference
        SQL
      end

      # overrides.csv : target = reference_name (production, taxon, production_system),
      # « kind:code » (area) ou « source:reference » (pest).
      def apply_overrides
        query <<~SQL
          DROP TABLE IF EXISTS #{name}.overrides_parsed;
          CREATE TABLE #{name}.overrides_parsed AS
            SELECT document_id, target_kind, action,
                   CASE WHEN target_kind IN ('area', 'pest') THEN split_part(target, ':', 1) ELSE target END AS key1,
                   CASE WHEN target_kind IN ('area', 'pest') THEN substr(target, strpos(target, ':') + 1) END AS key2
              FROM #{name}.overrides;
        SQL
        return if query("SELECT count(*) FROM #{name}.overrides_parsed").getvalue(0, 0).to_i.zero?

        unknown = values("SELECT document_id FROM #{name}.overrides_parsed WHERE document_id NOT IN (SELECT id FROM registered_rd_agri_documents)")
        raise "#{name} : overrides : document inconnu : #{unknown.join(', ')}" if unknown.any?

        {
          'production' => ['registered_rd_agri_document_productions', { 'production' => 'o.key1' }],
          'taxon' => ['registered_rd_agri_document_taxa', { 'taxon' => 'o.key1' }],
          'production_system' => ['registered_rd_agri_document_production_systems', { 'production_system' => 'o.key1' }],
          'area' => ['registered_rd_agri_document_areas', { 'area_kind' => 'o.key1', 'area_code' => 'o.key2' }],
          'pest' => ['registered_rd_agri_document_pests', {
            'pest_source' => 'o.key1',
            'pest_reference' => 'o.key2',
            'label' => "COALESCE((SELECT min(v.label) FROM #{name}.voc_pest v WHERE v.source = o.key1 AND v.reference = o.key2), o.key2)"
          }]
        }.each do |kind, (table, columns)|
          keys = columns.reject { |column, _| column == 'label' }
          match = keys.map { |column, source| "t.#{column} = #{source}" }.join(' AND ')

          query <<~SQL
            DELETE FROM #{table} t
             USING #{name}.overrides_parsed o
             WHERE o.target_kind = '#{kind}' AND o.action = 'remove'
               AND t.document_id = o.document_id AND #{match};

            INSERT INTO #{table} (document_id, #{columns.keys.join(', ')}, channels)
              SELECT o.document_id, #{columns.values.join(', ')}, ARRAY['override']
                FROM #{name}.overrides_parsed o
               WHERE o.target_kind = '#{kind}' AND o.action = 'add'
            ON CONFLICT (document_id, #{keys.keys.join(', ')}) DO UPDATE
              SET channels = (SELECT array_agg(DISTINCT c ORDER BY c) FROM unnest(#{table}.channels || 'override'::text) c);
          SQL
        end
      end

      def check_integrity
        checks = {
          'zone inconnue' => <<~SQL,
            SELECT DISTINCT area_kind || ':' || area_code FROM registered_rd_agri_document_areas a
             WHERE NOT EXISTS (SELECT 1 FROM registered_administrative_areas r WHERE r.kind = a.area_kind AND r.code = a.area_code)
          SQL
          'système de production inconnu' => <<~SQL,
            SELECT DISTINCT production_system FROM registered_rd_agri_document_production_systems
             WHERE production_system NOT IN (SELECT name FROM master_nomenclatures WHERE nomenclature = 'production_systems')
          SQL
          'ravageur ou maladie inconnu' => <<~SQL
            SELECT DISTINCT pest_source || ':' || pest_reference FROM registered_rd_agri_document_pests p
             WHERE NOT ((p.pest_source = 'ephy_target' AND EXISTS (SELECT 1 FROM registered_phytosanitary_usages u WHERE u.target_name_label_fra = p.pest_reference))
                     OR (p.pest_source = 'issue_nature' AND EXISTS (SELECT 1 FROM master_nomenclatures n WHERE n.nomenclature = 'issue_natures' AND n.name = p.pest_reference)))
          SQL
        }
        checks.each do |label, sql|
          wrong = values(sql)
          raise "#{name} : #{label} : #{wrong.first(20).join(', ')}" if wrong.any?
        end
      end

      def report
        total = query('SELECT count(*) FROM registered_rd_agri_documents').getvalue(0, 0).to_i
        logger.debug "#{name} : #{total} documents"

        %w[productions taxa areas production_systems pests].each do |suffix|
          table = "registered_rd_agri_document_#{suffix}"
          row = query(<<~SQL).first
            SELECT count(DISTINCT document_id) AS documents, count(*) AS links FROM #{table}
          SQL
          channels = query(<<~SQL).map { |r| "#{r['channel']} #{r['documents']}" }.join(', ')
            SELECT channel, count(DISTINCT document_id) AS documents
              FROM (SELECT document_id, unnest(channels) AS channel FROM #{table}) c
             GROUP BY channel ORDER BY channel
          SQL
          ratio = total.zero? ? 0 : (100.0 * row['documents'].to_i / total).round(1)
          logger.debug "  #{suffix} : #{row['documents']} documents (#{ratio} %), #{row['links']} liens — #{channels}"
        end
      end

      def values(sql)
        query(sql).values.flatten
      end
  end
end
