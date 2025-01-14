module Datasources
  class Budgets < Base
    description 'Budgets'
    credits name: 'Trames de budgets de références', url: "https://ekylibre.com", provider: "Ekylibre SAS", licence: "CC-BY-SA 4.0", licence_url: "https://creativecommons.org/licenses/by-sa/4.0/deed.fr", updated_at: "2021-07-12"

    def collect
      FileUtils.cp Dir.glob('data/budgets/budgets.ods'), dir
    end

    def load
    end

    def self.table_definitions(builder)
      builder.table(:master_budgets, sql: <<-SQL).references(variant: [:master_variants, :reference_name], unit: [:master_units, :reference_name])
        CREATE TABLE master_budgets (
          activity_family character varying NOT NULL,
          budget_category character varying NOT NULL,
          variant character varying NOT NULL,
          mode character varying,
          proportionnal_key character varying,
          repetition integer NOT NULL,
          frequency character varying NOT NULL,
          start_month integer NOT NULL,
          quantity numeric(8,2) NOT NULL,
          unit_pretax_amount numeric(8,2) NOT NULL,
          tax_rate numeric(8,2) NOT NULL,
          unit character varying NOT NULL,
          direction character varying NOT NULL
        );
        CREATE INDEX master_budgets_variant ON master_budgets(variant);
      SQL
    end

    def normalize
      # load category
        s = Roo::OpenOffice.new(dir.join('budgets.ods'))

        # for each sheet of the ods file
        s.sheets.each do |sheet_name|
          s.sheet(sheet_name)
          # for each next line, load
          2.upto(s.last_row) do |row_number|
            # parse data
            next if s.cell('A', row_number).blank?
            budget_category = s.cell('A', row_number).to_s
            variant = s.cell('C', row_number).to_s
            mode = s.cell('D', row_number).to_s
            proportionnal = s.cell('E', row_number).to_s
            repetition = s.cell('F', row_number).to_i
            frequency = s.cell('G', row_number).to_s
            start_month = s.cell('H', row_number).to_i
            quantity = s.cell('I', row_number).to_s.gsub(",", ".").to_f
            price = s.cell('J', row_number).to_s.gsub(",", ".").to_f
            tax_rate = s.cell('K', row_number).to_s.gsub(",", ".").to_f
            unit = s.cell('L', row_number).to_s
            direction = s.cell('M', row_number).to_s
            # insert data
            query "INSERT INTO master_budgets
            (activity_family, budget_category, variant, mode, proportionnal_key, repetition, frequency, start_month, quantity, unit_pretax_amount, tax_rate, unit, direction)
            VALUES ('#{sheet_name}', '#{budget_category}', '#{variant}', '#{mode}', '#{proportionnal}', #{repetition}, '#{frequency}', #{start_month}, #{quantity}, #{price}, #{tax_rate}, '#{unit}', '#{direction}')"
          end
        end
    end

  end
end
