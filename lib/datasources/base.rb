module Datasources
  class Base
    extend Forwardable
    include Lexicon::Dsl::CreditsRecorder
    include Lexicon::Dsl::Description
    include Lexicon::Dsl::Python
    include Lexicon::Dsl::Resources

    # @return [Common::Database::Database]
    attr_reader :database
    # @return [Lexicon::Loader::Shp]
    attr_reader :shp_loader
    attr_reader :downloader, :logger

    def_delegators :@psql_wrapper, :load_sql
    def_delegators :@database, :query, :copy_data
    def_delegator :@shell, :execute
    def_delegator :@csv_fixer, :fix, :fix_csv

    class << self
      # @return [String]
      def datasource_name
        name.split('::').last.underscore
      end

      def composite?
        false
      end
    end

    def initialize(downloader:, database:, logger:, csv_loader:, roo_loader:, shp_loader:, shell:, csv_fixer:, psql_wrapper:)
      @downloader = downloader
      @database = database
      @logger = logger
      @csv_loader = csv_loader
      @roo_loader = roo_loader
      @shp_loader = shp_loader
      @shell = shell
      @csv_fixer = csv_fixer
      @psql_wrapper = psql_wrapper
    end

    def load_shp(file, **options)
      shp_loader.load(file, **options, search_path: [name, database.search_path])
    end

    def dir
      downloader.base_dir
    end

    def name
      datasource_name
    end

    def datasource_name
      self.class.datasource_name
    end

    def load_csv(file, table, col_sep: ',', **options)
      @csv_loader.load(file, table_name: table, search_path: @database.search_path, col_sep: col_sep)
    end

    def load_xls(file)
      @roo_loader.load_xls(file, search_path: @database.search_path)
    end

    def load_xlsx(file)
      @roo_loader.load_xlsx(file, search_path: @database.search_path)
    end

    def load_roo(file, extension:)
      @roo_loader.load_roo(file, extension: extension, search_path: @database.search_path)
    end

    def collect
    end

    def load
    end

    def normalize
    end

    def log(message)
      logger.log("Deprecated call to Datasource.log".red)
      logger.log message
    end

    def unzip(source, destination)
      FileUtils.rm_rf(destination) if File.exist?(destination)
      Zip::File.open(source) do |zip_file|
        zip_file.each do |f|
          f_path = File.join(destination, f.name)
          FileUtils.mkdir_p(File.dirname(f_path))
          zip_file.extract(f, f_path)
        end
      end
    end

    def insert_translations(datasource, temp_table, table)
      query "INSERT INTO master_translations (id, fra, eng)
      SELECT CONCAT('#{table}_', reference_name), fra, eng
      FROM #{datasource}.#{temp_table}"
    end

  end
end
