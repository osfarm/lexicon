# frozen_string_literal: true

module Lexicon
  module Datasource
    module Executor
      class Base
        include Common::Mixin::LoggerAware

        def initialize(database_factory:, downloader_factory:, csv_loader:, roo_loader:, shp_loader:, psql_wrapper:, shell:, database_url:)
          @csv_loader = csv_loader
          @database_factory = database_factory
          @downloader_factory = downloader_factory
          @roo_loader = roo_loader
          @shp_loader = shp_loader
          @psql_wrapper = psql_wrapper
          @shell = shell
          @database_url = database_url
        end

        def build_datasource(klass)
          downloader = @downloader_factory.create(klass.datasource_name)

          klass.new(
            downloader: downloader,
            database: @database_factory.new_instance(url: @database_url),
            logger: logger,
            csv_loader: @csv_loader,
            roo_loader: @roo_loader,
            shp_loader: @shp_loader,
            shell: @shell,
            csv_fixer: CsvFixer.new(downloader.base_dir),
            psql_wrapper: @psql_wrapper
          )
        end
      end
    end
  end
end
