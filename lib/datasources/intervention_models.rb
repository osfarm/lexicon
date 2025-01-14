module Datasources
  class InterventionModels < Base
    description 'Intervention models references used for ITKs'
    credits name: 'Modèles interventions', url: "https://ekylibre.com", provider: "Ekylibre SAS", licence: "CC-BY-SA 4.0", licence_url: "https://creativecommons.org/licenses/by-sa/4.0/deed.fr", updated_at: "2021-09-10"

    def collect
      FileUtils.cp('data/intervention_models/intervention_models.ods', dir)
    end

    def self.table_definitions(builder)
      builder.table :intervention_models, sql: <<-SQL
        CREATE TABLE intervention_models (
          reference_name character varying PRIMARY KEY NOT NULL,
          name jsonb,
          category_name jsonb,
          number character varying,
          procedure_reference character varying NOT NULL,
          working_flow numeric(19,4),
          working_flow_unit character varying
        );

        CREATE INDEX intervention_models_reference_name ON intervention_models(reference_name);
        CREATE INDEX intervention_models_name ON intervention_models(name);
        CREATE INDEX intervention_models_procedure_reference ON intervention_models(procedure_reference);
      SQL

      builder.table(:intervention_model_items, sql: <<-SQL).references(intervention_model_id: [:intervention_models, :reference_name])
        CREATE TABLE intervention_model_items (
          reference_name character varying PRIMARY KEY NOT NULL,
          procedure_item_reference character varying NOT NULL,
          article_reference character varying,
          indicator_name character varying,
          indicator_value numeric(19,4),
          indicator_unit character varying,
          intervention_model_id character varying
        );

        CREATE INDEX intervention_model_items_reference_name ON intervention_model_items(reference_name);
        CREATE INDEX intervention_model_items_procedure_item_reference ON intervention_model_items(procedure_item_reference);
        CREATE INDEX intervention_model_items_article_reference ON intervention_model_items(article_reference);
        CREATE INDEX intervention_model_items_intervention_model_id ON intervention_model_items(intervention_model_id);
      SQL
    end

    def normalize
      s = Roo::OpenOffice.new(dir.join('intervention_models.ods'))

      # for each sheet of the ods itk file
      s.sheets.each do |sheet_name|

        s.sheet(sheet_name)

        previous_item_footprint = ''
        # for each next line, load
        2.upto(s.last_row) do |row_number|
          next if s.cell('A', row_number).blank?
          # build attributes from line
          # technical_worflow_procedures
          number = s.cell('A', row_number).to_s
          name = s.cell('B', row_number).to_s
          category_name = sheet_name
          procedure_reference = (s.cell('C', row_number).blank? ? nil : s.cell('C', row_number).to_s)
          id = s.cell('D', row_number).to_s.gsub(",", "_")
          working_flow = (s.cell('J', row_number).blank? ? '0' : s.cell('J', row_number).to_f)
          working_flow_unit = (s.cell('K', row_number).blank? ? '' : s.cell('K', row_number).to_s)

          footprint = id

          if previous_item_footprint != footprint
            query "INSERT INTO intervention_models
              (reference_name, name, category_name, number, procedure_reference, working_flow, working_flow_unit)
              VALUES ('#{id}', ('{\"fra\": \"' || '#{name}' || '\"}')::jsonb, ('{\"fra\": \"' || '#{category_name}' || '\"}')::jsonb, '#{number}', '#{procedure_reference}', #{working_flow}, '#{working_flow_unit}')"
            previous_item_footprint = footprint
          end

          procedure_item_reference = s.cell('E', row_number).to_s
          article_reference = s.cell('F', row_number).to_s
          procedure_item_id = "#{id}_#{procedure_item_reference}_#{article_reference}"
          indicator_name = s.cell('G', row_number).blank? ? '' : s.cell('G', row_number).to_s
          indicator_value = s.cell('H', row_number).blank? ? 0.0 : s.cell('H', row_number).to_f
          indicator_unit = s.cell('I', row_number).blank? ? '' : s.cell('I', row_number).to_s
          intervention_model_id = id

          query "INSERT INTO intervention_model_items
            (reference_name, procedure_item_reference, article_reference, indicator_name, indicator_value, indicator_unit, intervention_model_id)
            VALUES ('#{procedure_item_id}', '#{procedure_item_reference}', '#{article_reference}', '#{indicator_name}', #{indicator_value}, '#{indicator_unit}', '#{intervention_model_id}')"

        end
      end
    end
  end
end
