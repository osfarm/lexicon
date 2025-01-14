# frozen_string_literal: true

module Lexicon
  class MobileDumper
    attr_reader :db_url, :shell

    def initialize(target_dir:, shell:, db_url:)
      @target_dir = target_dir
      @shell = shell
      @db_url = db_url
    end

    def dump(version:, schema: :lexicon)
      version_dir = @target_dir.join(version)
      FileUtils.mkdir_p(version_dir)
      # TODO: use HEREDOC
      # rubocop:disable Layout/LineLength
      shell.execute "psql '#{db_url}' -c \"COPY (WITH prod AS (SELECT id, specie, human_name_fra, agroedi_crop_code, pfi_crop_code, season FROM #{schema}.master_production_natures) SELECT regexp_replace(json_agg(prod)::text, E' \n ', '', 'g') FROM prod) TO STDOUT\" > #{version_dir.join('production_natures.json')}"
      shell.execute "psql '#{db_url}' -c \"COPY (WITH selection AS (SELECT * FROM #{schema}.registered_phytosanitary_products) SELECT regexp_replace(json_agg(selection)::text, E' \n ', '', 'g') FROM selection) TO STDOUT\" > #{version_dir.join('phytosanitary_products.json')}"
      shell.execute "psql '#{db_url}' -c \"COPY (WITH selection AS (SELECT nomen.name, nomen.label->>'fra' fra, nomen.label->>'eng' eng FROM open_nomenclature.varieties AS nomen LEFT JOIN #{schema}.registered_seeds AS gnis ON gnis.specie = nomen.name WHERE nomen.name = gnis.specie GROUP BY nomen.name, nomen.label ORDER BY fra ASC) SELECT regexp_replace(json_agg(selection)::text, E' \n ', '', 'g') FROM selection) TO STDOUT\" > #{version_dir.join('species.json')}"
      shell.execute "psql '#{db_url}' -c \"COPY (WITH selection AS (SELECT * FROM #{schema}.variants WHERE category = 'fertilizer') SELECT regexp_replace(json_agg(selection)::text, E' \n ', '', 'g') FROM selection) TO STDOUT\" > #{version_dir.join('fertilizers.json')}"
      shell.execute "psql '#{db_url}' -c \"COPY (WITH selection AS (SELECT product_id, MIN(dose_quantity) AS dose FROM #{schema}.registered_phytosanitary_usages WHERE dose_unit LIKE 'liter%' GROUP BY product_id ORDER BY product_id) SELECT regexp_replace(json_agg(selection)::text, E' \n ', '', 'g') FROM selection) TO STDOUT\" > #{version_dir.join('phytosanitary_doses.json')}"
      # rubocop:enable Layout/LineLength
    end
  end
end
