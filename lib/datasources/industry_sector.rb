module Datasources
  # Filières agricoles et appartenance des productions.
  #
  # Les filières sont hiérarchisées (sectors.csv). L'appartenance d'une
  # production est déclarée par règles (rules.csv) : une règle retient les
  # productions qui satisfont tous ses critères non vides (activity_family,
  # usage, taxon, crop_set, production). Les règles `exclude` retirent des
  # productions de la filière. La table produite est la fermeture : une
  # filière contient aussi les productions de ses sous-filières (direct = false).
  class IndustrySector < Base
    description 'Filières agricoles et appartenance des productions'
    credits name: 'Filières agricoles',
            url: 'https://ekylibre.com',
            provider: 'Ekylibre SAS',
            licence: 'CC-BY-SA 4.0',
            licence_url: 'https://creativecommons.org/licenses/by-sa/4.0/deed.fr',
            updated_at: '2026-09-15'
    depends_on :taxonomy, :open_nomenclature
    translations :industry_sectors

    RULE_CRITERIA = %w[activity_family usage taxon crop_set production].freeze

    def collect
      FileUtils.cp Dir.glob('data/industry_sector/*.csv'), dir
    end

    def load
      load_csv(dir.join('sectors.csv'), 'sectors')
      load_csv(dir.join('rules.csv'), 'rules')
    end

    def self.table_definitions(builder)
      builder.table(:master_industry_sectors, sql: <<~SQL).references(parent: [:master_industry_sectors, :reference_name])
        CREATE TABLE master_industry_sectors (
          reference_name character varying PRIMARY KEY NOT NULL,
          parent character varying,
          depth integer NOT NULL,
          translation_id character varying NOT NULL
        );

        CREATE INDEX master_industry_sectors_parent ON master_industry_sectors(parent);
      SQL

      builder.table(:master_industry_sector_productions, sql: <<~SQL).references(industry_sector: [:master_industry_sectors, :reference_name], production: [:master_productions, :reference_name])
        CREATE TABLE master_industry_sector_productions (
          industry_sector character varying NOT NULL,
          production character varying NOT NULL,
          direct boolean NOT NULL,
          PRIMARY KEY (industry_sector, production)
        );

        CREATE INDEX master_industry_sector_productions_production ON master_industry_sector_productions(production);
      SQL
    end

    def normalize
      check_prerequisites
      insert_sectors
      check_rules
      insert_memberships
      report
    end

    private

      def check_prerequisites
        {
          'master_productions' => 'SELECT count(*) FROM master_productions',
          'master_taxonomy' => 'SELECT count(*) FROM master_taxonomy',
          'master_nomenclatures (crop_sets)' => "SELECT count(*) FROM master_nomenclatures WHERE nomenclature = 'crop_sets'"
        }.each do |table, sql|
          next if query(sql).getvalue(0, 0).to_i.positive?

          raise "#{name} : #{table} est vide. Lancer d'abord : ./lexicon run taxonomy productions open_nomenclature"
        end
      end

      def insert_sectors
        unknown = values(<<~SQL)
          SELECT s.reference_name || ' → ' || s.parent
            FROM #{name}.sectors s
           WHERE NULLIF(s.parent, '') IS NOT NULL
             AND s.parent NOT IN (SELECT reference_name FROM #{name}.sectors)
        SQL
        raise "#{name} : parent inconnu dans sectors.csv : #{unknown.join(', ')}" if unknown.any?

        query "DELETE FROM master_translations WHERE id LIKE 'industry_sectors\\_%'"

        query <<~SQL
          WITH RECURSIVE tree(reference_name, parent, depth) AS (
            SELECT reference_name, NULL::varchar, 0
              FROM #{name}.sectors
             WHERE NULLIF(parent, '') IS NULL
            UNION ALL
            SELECT s.reference_name, s.parent, tree.depth + 1
              FROM #{name}.sectors s
              JOIN tree ON tree.reference_name = s.parent
             WHERE tree.depth < 20
          )
          INSERT INTO master_industry_sectors (reference_name, parent, depth, translation_id)
            SELECT reference_name, parent, depth, CONCAT('industry_sectors_', reference_name)
              FROM tree
        SQL

        orphans = values(<<~SQL)
          SELECT reference_name FROM #{name}.sectors
          EXCEPT SELECT reference_name FROM master_industry_sectors
        SQL
        raise "#{name} : cycle dans la hiérarchie des filières : #{orphans.join(', ')}" if orphans.any?

        insert_translations(name, 'sectors', 'industry_sectors')
      end

      def check_rules
        checks = {
          'filière inconnue' => "SELECT DISTINCT industry_sector FROM #{name}.rules WHERE industry_sector NOT IN (SELECT reference_name FROM master_industry_sectors)",
          'production inconnue' => "SELECT DISTINCT production FROM #{name}.rules WHERE NULLIF(production, '') IS NOT NULL AND production NOT IN (SELECT reference_name FROM master_productions)",
          'taxon inconnu' => "SELECT DISTINCT taxon FROM #{name}.rules WHERE NULLIF(taxon, '') IS NOT NULL AND taxon NOT IN (SELECT reference_name FROM master_taxonomy)",
          'crop_set inconnu' => "SELECT DISTINCT crop_set FROM #{name}.rules WHERE NULLIF(crop_set, '') IS NOT NULL AND crop_set NOT IN (SELECT name FROM master_nomenclatures WHERE nomenclature = 'crop_sets')",
          'règle sans critère' => "SELECT industry_sector FROM #{name}.rules WHERE #{RULE_CRITERIA.map { |c| "NULLIF(#{c}, '') IS NULL" }.join(' AND ')}",
          'exclude invalide' => "SELECT DISTINCT COALESCE(exclude, '') FROM #{name}.rules WHERE COALESCE(exclude, '') NOT IN ('true', 'false')"
        }
        checks.each do |label, sql|
          wrong = values(sql)
          raise "#{name} : #{label} dans rules.csv : #{wrong.join(', ')}" if wrong.any?
        end
      end

      def insert_memberships
        query <<~SQL
          DROP TABLE IF EXISTS #{name}.ancestors;
          CREATE TABLE #{name}.ancestors AS
            WITH RECURSIVE up(production, taxon, depth) AS (
              SELECT reference_name, specie, 0 FROM master_productions WHERE specie IS NOT NULL
              UNION ALL
              SELECT up.production, t.parent, up.depth + 1
                FROM up
                JOIN master_taxonomy t ON t.reference_name = up.taxon
               WHERE t.parent IS NOT NULL AND up.depth < 30
            )
            SELECT DISTINCT production, taxon FROM up;

          DROP TABLE IF EXISTS #{name}.crop_set_taxa;
          CREATE TABLE #{name}.crop_set_taxa AS
            SELECT name AS crop_set, jsonb_array_elements_text(properties->'varieties') AS taxon
              FROM master_nomenclatures
             WHERE nomenclature = 'crop_sets';

          DROP TABLE IF EXISTS #{name}.matches;
          CREATE TABLE #{name}.matches AS
            SELECT r.industry_sector, p.reference_name AS production, r.exclude = 'true' AS exclude
              FROM #{name}.rules r
              JOIN master_productions p
                ON (NULLIF(r.activity_family, '') IS NULL OR p.activity_family = r.activity_family)
               AND (NULLIF(r.usage, '') IS NULL OR p.usage = r.usage)
               AND (NULLIF(r.production, '') IS NULL OR p.reference_name = r.production)
               AND (NULLIF(r.taxon, '') IS NULL OR EXISTS (
                     SELECT 1 FROM #{name}.ancestors a WHERE a.production = p.reference_name AND a.taxon = r.taxon))
               AND (NULLIF(r.crop_set, '') IS NULL OR EXISTS (
                     SELECT 1 FROM #{name}.ancestors a
                       JOIN #{name}.crop_set_taxa c ON c.taxon = a.taxon
                      WHERE a.production = p.reference_name AND c.crop_set = r.crop_set));

          WITH RECURSIVE direct AS (
            SELECT industry_sector, production FROM #{name}.matches WHERE NOT exclude
            EXCEPT
            SELECT industry_sector, production FROM #{name}.matches WHERE exclude
          ), descendants(root, node) AS (
            SELECT reference_name, reference_name FROM master_industry_sectors
            UNION ALL
            SELECT d.root, s.reference_name
              FROM descendants d
              JOIN master_industry_sectors s ON s.parent = d.node
          )
          INSERT INTO master_industry_sector_productions (industry_sector, production, direct)
            SELECT d.root, x.production, bool_or(d.root = d.node)
              FROM descendants d
              JOIN direct x ON x.industry_sector = d.node
             GROUP BY d.root, x.production
        SQL
      end

      def report
        query(<<~SQL).each { |row| logger.debug "  #{row['industry_sector']} : #{row['total']} production(s) dont #{row['direct']} directe(s)" }
          SELECT industry_sector, count(*) AS total, count(*) FILTER (WHERE direct) AS direct
            FROM master_industry_sector_productions
           GROUP BY industry_sector
           ORDER BY industry_sector
        SQL

        uncovered = lambda do |families|
          values(<<~SQL)
            SELECT reference_name FROM master_productions p
             WHERE activity_family IN (#{families.map { |f| "'#{f}'" }.join(', ')})
               AND NOT EXISTS (SELECT 1 FROM master_industry_sector_productions m WHERE m.production = p.reference_name)
             ORDER BY 1
          SQL
        end

        animals = uncovered.call(%w[animal_farming])
        raise "#{name} : productions animales sans filière : #{animals.join(', ')}" if animals.any?

        plants = uncovered.call(%w[plant_farming vine_farming])
        logger.warn "#{name} : #{plants.size} production(s) végétale(s) sans filière : #{plants.join(', ')}" if plants.any?
      end

      def values(sql)
        query(sql).values.flatten
      end
  end
end
