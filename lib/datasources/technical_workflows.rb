module Datasources
  class TechnicalWorkflows < Base
    description 'Technical workflows references'
    credits name: 'Séquence d interventions', url: "https://ekylibre.com", provider: "Ekylibre SAS", licence: "CC-BY-SA 4.0", licence_url: "https://creativecommons.org/licenses/by-sa/4.0/deed.fr", updated_at: "2021-09-10"

    def collect
      # for each ods files in data/itk folder
      FileUtils.cp Dir.glob('data/technical_workflows/ITKs_*.ods'), dir
      #FileUtils.cp Dir.glob('data/itk/*.xslx') ,dir
    end

    def load
      # for each ods files in data/itk folder
      # load_roo(dir.join('equipments.ods'), extension: :ods)
    end

    # TODO: REFERENCES?
    def self.table_definitions(builder)
      builder.table(:technical_workflows, sql: <<-SQL).references(production_reference_name: [:master_productions, :reference_name])
        CREATE TABLE technical_workflows (
          reference_name character varying PRIMARY KEY NOT NULL,
          family character varying,
          production_reference_name character varying,
          production_system character varying,
          start_day integer,
          start_month integer,
          unit character varying,
          life_state character varying,
          life_cycle character varying,
          plant_density integer,
          translation_id character varying NOT NULL
        );

        CREATE INDEX technical_workflows_reference_name ON technical_workflows(reference_name);
        CREATE INDEX technical_workflows_family ON technical_workflows(family);
        CREATE INDEX technical_workflows_production_reference_name ON technical_workflows(production_reference_name);
      SQL

      builder.table(:technical_workflow_procedures, sql: <<-SQL).references(technical_workflow_id: [:technical_workflows, :reference_name])
        CREATE TABLE technical_workflow_procedures (
          reference_name character varying PRIMARY KEY NOT NULL,
          position integer NOT NULL,
          name jsonb NOT NULL,
          repetition integer,
          frequency character varying,
          period character varying,
          bbch_stage character varying,
          procedure_reference character varying NOT NULL,
          technical_workflow_id character varying NOT NULL
        );

        CREATE INDEX technical_workflows_procedures_reference_name ON technical_workflow_procedures(reference_name);
        CREATE INDEX technical_workflows_procedures_technical_workflow_id ON technical_workflow_procedures(technical_workflow_id);
        CREATE INDEX technical_workflows_procedures_procedure_reference ON technical_workflow_procedures(procedure_reference);
      SQL

      builder.table(:technical_workflow_procedure_items, sql: <<-SQL).references(technical_workflow_procedure_id: [:technical_workflow_procedures, :reference_name])
        CREATE TABLE technical_workflow_procedure_items (
          reference_name character varying PRIMARY KEY NOT NULL,
          actor_reference character varying,
          procedure_item_reference character varying,
          article_reference character varying,
          quantity numeric(19,4),
          unit character varying,
          procedure_reference character varying NOT NULL,
          technical_workflow_procedure_id character varying NOT NULL
        );

        CREATE INDEX technical_workflow_procedure_items_reference_name ON technical_workflow_procedure_items(reference_name);
        CREATE INDEX technical_workflow_procedure_items_technical_workflow_pro_id ON technical_workflow_procedure_items(technical_workflow_procedure_id);
        CREATE INDEX technical_workflow_procedure_items_procedure_reference ON technical_workflow_procedure_items(procedure_reference);
      SQL
    end

    def normalize
      query "DELETE FROM master_translations WHERE id LIKE 'technical_workflows%'"
      # for each ods file, load data.
      Dir.glob(dir.join('ITKs_*.ods')).each do |file|

        s = Roo::OpenOffice.new(file)

        # for each sheet of the ods itk file
        s.sheets.each do |sheet_name|

          s.sheet(sheet_name)

          # build attributes from header and first line
          # technical_workflows
          family = s.cell('A', 2).to_s
          production_reference_name = s.cell('B', 2).to_s
          production_system = s.cell('C', 2).to_s
          name = s.cell('D', 2).to_s.gsub("'", " ")
          d = Date.parse(s.cell('E', 2).to_s)
          start_day = d.day.to_i
          start_month = d.month.to_i
          unit = s.cell('F', 2).to_s
          life_state = (s.cell('G', 2).blank? ? '1' : s.cell('G', 2).to_s)
          life_cycle = (s.cell('H', 2).blank? ? 'annual' : s.cell('H', 2).to_s)
          plant_density = (s.cell('I', 2).blank? ? 'NULL' : s.cell('I', 2).to_i)
          id = "#{family}_#{production_reference_name}_#{production_system}_#{sheet_name}"

          query "INSERT INTO technical_workflows
          (reference_name, family, production_reference_name, production_system, start_day, start_month, unit, life_state, life_cycle, plant_density, translation_id)
          VALUES ('#{id}', '#{family}', '#{production_reference_name}', '#{production_system}',
            #{start_day}, #{start_month}, '#{unit}',
             '#{life_state}', '#{life_cycle}', #{plant_density}, CONCAT('technical_workflows_', '#{id}'))"

          query "INSERT INTO master_translations (id, fra, eng)
          VALUES (CONCAT('technical_workflows_', '#{id}'), '#{name}', '#{name}')"

          previous_item_footprint = ''
          # for each next line, load
          4.upto(s.last_row) do |row_number|
            next if s.cell('A', row_number).blank?
            # build attributes from line
            # technical_workflow_procedures
            position = s.cell('A', row_number).to_i
            procedure_name = s.cell('B', row_number).to_s
            repetition = (s.cell('C', row_number).blank? ? 1 : s.cell('C', row_number).to_i)
            frequency = (s.cell('D', row_number).blank? ? 'per_year' : s.cell('D', row_number).to_s)
            period = (s.cell('E', row_number).blank? ? '0' : s.cell('E', row_number).to_s)
            bbch_stage = (s.cell('L', row_number).blank? ? '-' : s.cell('L', row_number).to_s)
            procedure_reference = s.cell('F', row_number).to_s
            technical_workflow_id = id
            technical_workflow_procedure_id = id + '_' + procedure_name + '_' + position.to_s
            footprint = position.to_s + '_' + procedure_name

            if previous_item_footprint != footprint

              query "INSERT INTO technical_workflow_procedures
              (reference_name, position, name, repetition, frequency, period, procedure_reference, technical_workflow_id)
              VALUES ('#{technical_workflow_procedure_id}', #{position}, ('{\"fra\": \"' || '#{procedure_name}' || '\"}')::jsonb, #{repetition}, '#{frequency}', '#{period}', '#{procedure_reference}', '#{technical_workflow_id}')"
              previous_item_footprint = footprint

            end

            next if s.cell('G', row_number).blank?

            actor_reference = s.cell('G', row_number).to_s
            procedure_item_reference = s.cell('H', row_number).to_s
            article_reference = s.cell('I', row_number).to_s
            quantity = s.cell('J', row_number).to_s.gsub(",", ".").to_f
            unit = s.cell('K', row_number).to_s
            technical_workflow_procedure_item_id = technical_workflow_procedure_id + '_' + procedure_item_reference + '_' + article_reference

            query "INSERT INTO technical_workflow_procedure_items
            (reference_name, actor_reference, procedure_item_reference, article_reference, quantity, unit, procedure_reference, technical_workflow_procedure_id)
            VALUES ('#{technical_workflow_procedure_item_id}', '#{actor_reference}', '#{procedure_item_reference}', '#{article_reference}', #{quantity}, '#{unit}', '#{procedure_name}', '#{technical_workflow_procedure_id}')"

          end
        end
      end
    end
  end
end
