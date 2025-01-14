module Datasources
  class TechnicalWorkflowSequences < Base
    description 'Technical workflows chaining for multiannual production'
    credits name: 'Sequence de références des modèles d interventions', url: "https://ekylibre.com", provider: "Ekylibre SAS", licence: "CC-BY-SA 4.0", licence_url: "https://creativecommons.org/licenses/by-sa/4.0/deed.fr", updated_at: "2020-02-12"

    def collect
      FileUtils.cp Dir.glob('data/technical_workflow_sequences/Multiannuals.ods'), dir
    end

    def self.table_definitions(builder)
      builder.table(:technical_sequences, sql: <<-SQL).references(production_reference_name: [:master_productions, :reference_name])
        CREATE TABLE technical_sequences (
          reference_name character varying PRIMARY KEY NOT NULL,
          family character varying,
          production_reference_name character varying NOT NULL,
          production_system character varying,
          translation_id character varying NOT NULL
        );

        CREATE INDEX technical_sequences_reference_name ON technical_sequences(reference_name);
        CREATE INDEX technical_sequences_family ON technical_sequences(family);
        CREATE INDEX technical_sequences_production_reference_name ON technical_sequences(production_reference_name);
      SQL

      builder.table(:technical_workflow_sequences, sql: <<-SQL).references(technical_workflow_id: [:technical_workflows, :reference_name], technical_sequence_id: [:technical_sequences, :reference_name])
        CREATE TABLE technical_workflow_sequences (
          technical_sequence_id character varying NOT NULL,
          year_start integer,
          year_stop integer,
          technical_workflow_id character varying NOT NULL
        );

        CREATE INDEX technical_workflow_sequences_technical_sequence_id ON technical_workflow_sequences(technical_sequence_id);
        CREATE INDEX technical_workflow_sequences_technical_workflow_id ON technical_workflow_sequences(technical_workflow_id);
      SQL
    end

    def normalize
      query "DELETE FROM master_translations WHERE id LIKE 'technical_sequences%'"
      # for each sheet of the file, load data.
      s = Roo::OpenOffice.new(dir.join('Multiannuals.ods'))

      # for each sheet of the ods itk file
      s.sheets.each do |sheet_name|

        s.sheet(sheet_name)

        # build attributes from header and first line
        # technical_workflows
        family = s.cell('A', 2).to_s
        production_reference_name = s.cell('B', 2).to_s
        production_system = s.cell('C', 2).to_s
        name = s.cell('D', 2).to_s.gsub("'", " ")
        technical_sequence_id = sheet_name.to_s

        query "INSERT INTO technical_sequences
          (reference_name, family, production_reference_name, production_system, translation_id)
          VALUES ('#{technical_sequence_id}', '#{family}', '#{production_reference_name}', '#{production_system}',
          CONCAT('technical_sequences_', '#{technical_sequence_id}'))"

        query "INSERT INTO master_translations (id, fra, eng)
          VALUES (CONCAT('technical_sequences_', '#{technical_sequence_id}'), '#{name}', '#{name}')"

        # for each next line, load
        4.upto(s.last_row) do |row_number|
          next if s.cell('A', row_number).blank?
          # build attributes from line
          # technical_workflow_procedures
          year_start = s.cell('A', row_number).to_i
          year_stop = s.cell('B', row_number).to_i
          procedure_reference = s.cell('C', row_number).to_s
          technical_workflow_id = "#{family}_#{production_reference_name}_#{procedure_reference}"

          query "INSERT INTO technical_workflow_sequences
            (technical_sequence_id, year_start, year_stop, technical_workflow_id)
            VALUES ('#{technical_sequence_id}', #{year_start}, #{year_stop}, '#{technical_workflow_id}')"

        end
      end
    end
  end
end
