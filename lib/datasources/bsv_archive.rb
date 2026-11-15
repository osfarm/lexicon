# frozen_string_literal: true

require 'zip'

module Datasources
  # The archive of the PestObserver project on data.gouv.fr: 40 829 texts of plant health bulletins, the
  # Avertissements agricoles of the regional services of plant protection (TEI XML, 1960-2010, OCR of medium quality
  # before 2000) and the BSV of 2009 to 2016 as the sites of the DRAAF then published them. Catalogue and full
  # text only, no risk is extracted: `bsv` reads the bulletins of today.
  #
  # `collect` downloads the zip once (173 MB); `load` reads it without unpacking it (`Documents`) and `normalize`
  # makes the searchable table (`doc/datasources/bsv_archive.md`).
  class BsvArchive < Base
    description "Archive des bulletins de santé du végétal et des Avertissements agricoles (PestObserver, 1960-2016) : catalogue et texte intégral"
    credits name: 'Archive en agro-écologie de BSV (PestObserver)',
            url: 'https://www.data.gouv.fr/fr/datasets/archive-en-agro-ecologie-de-bsv-bulletins-de-sante-du-vegetal/',
            provider: 'Projet PestObserver',
            licence: 'CC-BY',
            licence_url: 'https://creativecommons.org/licenses/by/4.0/',
            updated_at: '2016-12-01'

    DATASET = 'archive-en-agro-ecologie-de-bsv-bulletins-de-sante-du-vegetal'
    ZIP = 'reportsOCR.zip'

    def collect
      resource = data_gouv_resources(DATASET).find { |one| one['title'] == ZIP }
      raise "#{ZIP} is no longer listed in the dataset #{DATASET}" unless resource

      fetch(resource['url'], ZIP)
    end

    def load
      documents = Documents.new
      counts = Hash.new(0)
      CSV.open(dir.join('documents.csv'), 'w') do |csv|
        csv << Documents::COLUMNS
        Zip::File.open(dir.join(ZIP).to_s) do |zip|
          zip.each do |entry|
            next unless entry.file? && entry.name.match?(/\.(?:txt|xml)\z/)

            row = documents.row(entry.name, entry.get_input_stream.read.force_encoding('UTF-8'))
            csv << row
            values = Documents::COLUMNS.zip(row).to_h
            counts[values['kind']] += 1
            counts['without region'] += 1 if values['regions'].empty?
            counts['without date'] += 1 if values['published_on'].nil?
            counts['without year'] += 1 if values['year'].nil?
            counts['without sector'] += 1 if values['sectors'].empty?
          end
        end
      end
      load_csv(dir.join('documents.csv'), 'documents')
      puts "BSV archive: #{counts.sort.map { |what, n| "#{n} #{what}" }.join(', ')}"
    end

    def self.table_definitions(builder)
      builder.table(:registered_bsv_archive_documents, sql: <<~SQL)
        CREATE TABLE registered_bsv_archive_documents (
          id character varying PRIMARY KEY NOT NULL,
          file_name character varying NOT NULL,
          kind character varying NOT NULL,
          old_regions character varying[] NOT NULL,
          regions character varying[] NOT NULL,
          department_codes character varying[] NOT NULL,
          sectors character varying[] NOT NULL,
          published_on date,
          year integer,
          title character varying,
          text text NOT NULL,
          search tsvector NOT NULL DEFAULT ''::tsvector
        );

        CREATE INDEX registered_bsv_archive_documents_search ON registered_bsv_archive_documents USING GIN (search);
        CREATE INDEX registered_bsv_archive_documents_department_codes ON registered_bsv_archive_documents USING GIN (department_codes);
        CREATE INDEX registered_bsv_archive_documents_year ON registered_bsv_archive_documents(year);
      SQL
    end

    def normalize
      array = ->(column) { "string_to_array(NULLIF(#{column}, ''), '|')" }
      unaccented = ->(column) { "translate(lower(#{column}), '#{RdAgri::ACCENTED}', '#{RdAgri::UNACCENTED}')" }
      # The title weighs more than the text; accents are removed, as in `rd_agri`
      query <<~SQL
        INSERT INTO registered_bsv_archive_documents
          (id, file_name, kind, old_regions, regions, department_codes, sectors, published_on, year, title, text, search)
        SELECT id, file_name, kind, COALESCE(#{array.call('old_regions')}, '{}'), COALESCE(#{array.call('regions')}, '{}'),
               COALESCE(#{array.call('department_codes')}, '{}'), COALESCE(#{array.call('sectors')}, '{}'),
               NULLIF(published_on, '')::date, NULLIF(year, '')::integer, NULLIF(title, ''), COALESCE(text, ''),
               setweight(to_tsvector('french', #{unaccented.call("COALESCE(title, '')")}), 'A') ||
                 setweight(to_tsvector('french', #{unaccented.call("COALESCE(text, '')")}), 'B')
          FROM #{name}.documents
      SQL
    end
  end
end
