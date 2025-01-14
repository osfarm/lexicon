require 'datasources/base'

module Datasources
  class PhenologicalStages < Base
    description 'Phenological stages'
    credits name: 'Stades phénologiques', url: "https://ekylibre.com", provider: "Ekylibre SAS", licence: "CC-BY-SA 4.0", licence_url: "https://creativecommons.org/licenses/by-sa/4.0/deed.fr", updated_at: "2020-02-12"

    def collect
      FileUtils.cp Dir.glob('data/phenological_stages/vitis_phenological_stages - phenological_stages.csv'), dir
      FileUtils.cp Dir.glob('data/phenological_stages/crop_phenological_stages - phenological_stages.csv'), dir
    end

    def load
      load_csv(dir.join('vitis_phenological_stages - phenological_stages.csv'), 'vitis_phenological_stages')
      load_csv(dir.join('crop_phenological_stages - phenological_stages.csv'), 'crop_phenological_stages')
    end

    def self.table_definitions(builder)
      builder.table :master_phenological_stages, sql: <<-SQL
        CREATE TABLE master_phenological_stages (
          id character varying PRIMARY KEY NOT NULL,
          bbch_code character varying NOT NULL,
          variety character varying NOT NULL,
          biaggiolini character varying,
          eichhorn_lorenz character varying,
          chasselas_date character varying,
          label jsonb,
          description jsonb
        );
      SQL
    end

    def normalize
      query <<-SQL
        INSERT INTO master_phenological_stages (id, bbch_code, variety, biaggiolini, eichhorn_lorenz, chasselas_date, label, description)
          SELECT CONCAT(bbch_code, '-vitis'), bbch_code, 'vitis', biaggiolini, eichhorn_lorenz, chasselas_date, CONCAT('{"fra":"', label_fr, '"}')::JSONB, CONCAT('{"fra":"', description_fr, '"}')::JSONB
          FROM phenological_stages.vitis_phenological_stages
      SQL

      query <<-SQL
        INSERT INTO master_phenological_stages (id, bbch_code, variety, label)
          SELECT CONCAT(bbch, '-', variety), bbch, variety, CONCAT('{"fra":"', label, '"}')::JSONB
          FROM phenological_stages.crop_phenological_stages
      SQL
    end

  end
end
