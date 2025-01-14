# frozen_string_literal: true

module Lexicon
  class Application
    attr_reader :args

    def initialize(args, root:)
      @args = args
      @root = root
    end

    def start
      container = Container.new
      register_parameters(container, root: @root)
      register_services(container)
      register_datasources(container)

      Cli.start(args, container: container)
    end

    private

      def register_parameters(container, root:)
        container.namespace :parameter do
          namespace :database do
            register(:host) { ENV.fetch('POSTGRES_HOST', 'localhost') }
            register(:port) { ENV.fetch('POSTGRES_PORT', '5432') }
            register(:name) { ENV.fetch('POSTGRES_NAME', 'lexicon') }
            register(:user) { ENV.fetch('POSTGRES_USER', nil) }
            register(:password) { ENV.fetch('POSTGRES_PASSWORD', nil) }
            register(:url) do
              user = container.resolve('parameter.database.user')
              password = container.resolve('parameter.database.password')
              host = container.resolve('parameter.database.host')
              port = container.resolve('parameter.database.port')
              name = container.resolve('parameter.database.name')

              credentials = if password.present?
                              "#{user}:#{password}"
                            else
                              user
                            end

              "postgres://#{credentials}@#{host}:#{port}/#{name}"
            end
          end

          namespace :minio do
            register(:host) { ENV.fetch('MINIO_HOST', 'https://io.ekylibre.dev') }
            register(:access_key) { ENV.fetch('MINIO_ACCESS_KEY', nil) }
            register(:secret_key) { ENV.fetch('MINIO_SECRET_KEY', nil) }
          end

          namespace :production do
            register(:config) do
              file = container.resolve('parameter.production.config.file')

              if file.exist?
                YAML.safe_load(File.read(file)).transform_keys(&:to_sym)
              else
                {}
              end
            end

            namespace :database do
              register(:url) do
                user = ENV.fetch('PRODUCTION_DATABASE_USER', 'postgres')
                password = ENV.fetch('PRODUCTION_DATABASE_PASSWORD', '')
                host = ENV.fetch('PRODUCTION_DATABASE_HOST', '127.0.0.1')
                port = ENV.fetch('PRODUCTION_DATABASE_PORT', '5432')
                name = ENV.fetch('PRODUCTION_DATABASE_NAME', 'lexicon')

                credentials = if password.present?
                                "#{user}:#{password}"
                              else
                                user
                              end

                "postgres://#{credentials}@#{host}:#{port}/#{name}"
              end
            end
          end

          namespace :mobile do
            register(:root, memoize: true) { container.resolve('parameter.out.root').join 'zero-v3' }
          end
          register(:root, memoize: true) { Pathname.new(root) }
          namespace :raw do
            register(:root, memoize: true) { container.resolve('parameter.root').join 'raw' }
          end
          namespace :out do
            register(:root, memoize: true) { container.resolve('parameter.root').join 'out' }
          end
          namespace :flavors do
            register(:root, memoize: true) { container.resolve('parameter.resources.root').join('flavors') }
          end
          namespace :data do
            register(:root, memoize: true) { container.resolve('parameter.root').join 'data' }
          end
          namespace :version do
            register(:file, memoize: true) { container.resolve('parameter.root').join 'VERSION' }
          end
          namespace :resources do
            register(:root, memoize: true) { container.resolve('parameter.root').join('resources') }

            register(:flavor_schema_path, memoize: true) { container.resolve('parameter.resources.root').join('flavor.schema.json') }
            register(:lexicon_schema_path, memoize: true) { container.resolve('parameter.resources.root').join('lexicon.schema.json') }
          end
        end
      end

      def register_services(container)
        container.register(:csv_loader) { Loader::Csv.new(psql: container.resolve('database.psql')) }

        container.namespace :credits do
          register(:builder) { CreditsBuilder.new }
        end

        container.register(:database, memoize: true) do
          container.resolve('database.factory')
                   .new_instance(url: container.resolve('parameter.database.url'))
        end
        container.namespace :database do
          register(:factory, memoize: true) do
            Common::Database::Factory.new(
              verbose: container.resolve('config.verbose')
            )
          end
          register(:cleaner, memoize: true) { Database::Cleaner.new(container.resolve('database')) }
          register(:psql, memoize: true) do
            Common::Psql.new(
              url: container.resolve('parameter.database.url'),
              executor: container.resolve('shell_executor')
            )
          end
          register(:dumper, memoize: true) do
            Database::DataDumper.new(
              shell: container.resolve('shell_executor'),
              db_url: container.resolve('parameter.database.url'),
              datasource_classes: container.resolve('datasource.all'),
              database_factory: container.resolve('database.factory'),
              credits_builder: container.resolve('credits.builder'),
              table_definitions: container.resolve('database.schema.definitions'),
              package_creator: container.resolve('production.package.creator'),
              psql: container.resolve('database.psql')
            )
          end
          register(:mobile) do
            MobileDumper.new(
              target_dir: container.resolve('parameter.mobile.root'),
              shell: container.resolve('shell_executor'),
              db_url: container.resolve('parameter.database.url')
            )
          end
          register(:validator, memoize: true) do
            Database::Validation::Validator.new(
              database_factory: container.resolve('database.factory'),
              definitions: container.resolve('database.schema.definitions'),
        db_url: container.resolve('parameter.database.url'),
              fk_manager: container.resolve('database.schema.foreign_key_manager'),
            )
          end
          namespace :schema do
            register(:foreign_key_manager, memoize: true) do
              Database::Schema::ForeignKeyManager.new(
                container.resolve('database.schema.definitions')
              )
            end
            register(:table_definitions_factory, memoize: true) { Database::Schema::TableDefinitionsFactory.new }
            register(:definitions, memoize: true) do
              factory = container.resolve('database.schema.table_definitions_factory')
              datasource_definitions = container.resolve('datasource.all').map { |(name, klass)| factory.build(name.to_s, klass) }.compact
              credits_definition = factory.build('datasource_credits', Credits)

              [*datasource_definitions, credits_definition]
            end
          end
        end

        container.namespace(:datasource) do
          register(:executor, memoize: true) do
            parameters = {
              database_factory: container.resolve('database.factory'),
              runner: container.resolve('datasource.runner'),
              downloader_factory: container.resolve('downloader.factory'),
              csv_loader: container.resolve('csv_loader'),
              roo_loader: container.resolve('roo_loader'),
              shp_loader: container.resolve('shp_loader'),
              psql_wrapper: container.resolve('database.psql'),
              shell: container.resolve('shell_executor'),
              database_url: container.resolve('parameter.database.url'),
            }

            if container.resolve('config.parallel')
              Datasource::Executor::ParallelExecutor
            else
              Datasource::Executor::SequentialExecutor
            end.new(**parameters)
          end
          register(:all) { container.resolve('datasource.provider').all }
          register(:provider, memoize: true) do
            list = container.resolve('datasource.register').list

            Datasource::Provider.new(list.map { |service| container.resolve(service) })
          end
          register(:resource_collector) { Datasource::ResourceCollector.new(data_dir: container.resolve('parameter.data.root')) }
          register(:register, memoize: true) { Datasource::Register.new(container) }
          register(:runner, memoize: true) do
            Datasource::SimpleRunner.new(
              table_definition_factory: container.resolve('database.schema.table_definitions_factory'),
              resource_collector: container.resolve('datasource.resource_collector'),
              fk_manager: container.resolve('database.schema.foreign_key_manager')
            )
          end
          register(:name_runner, memoize: true) do
            Datasource::NameRunner.new(
              datasource_provider: container.resolve('datasource.provider'),
              executor: container.resolve('datasource.executor')
            )
          end
        end

        container.namespace :downloader do
          register(:factory) do
            DownloaderFactory.new(
              container.resolve('parameter.raw.root'),
              logger: container.resolve(:logger),
              executor: container.resolve(:shell_executor)
            )
          end
        end

        container.namespace(:flavor) do
          register(:loader, memoize: true) do
            Flavor::FlavorLoader.new(
              dir: container.resolve('parameter.flavors.root'),
              validator: container.resolve('flavor.schema_validator')
            )
          end
          register(:schema_validator, memoize: true) do
            container.resolve('flavor.schema_validator_factory').build
          end
          register(:schema_validator_factory, memoize: true) do
            Common::Schema::ValidatorFactory.new(
              container.resolve('parameter.resources.flavor_schema_path')
            )
          end
        end

        container.register(:logger, memoize: true) { ::Logger.new(STDOUT) }

        container.namespace(:minio) do
          register(:client) do
            Aws::S3::Client.new(
              endpoint: container.resolve('parameter.minio.host'),
              access_key_id: container.resolve('parameter.minio.access_key'),
              secret_access_key: container.resolve('parameter.minio.secret_key'),
              force_path_style: true,
              region: 'us-east-1'
            )
          end
        end

        container.register(:s3_client, memoize: true) do
          Common::Remote::S3Client.new(raw: container.resolve('minio.client'))
        end

        container.namespace :production do
          namespace :package do
            register(:creator, memoize: true) do
              Package::PackageCreator.new(
                dir: container.resolve('parameter.out.root'),
                hasher: container.resolve('production.package.hasher'),
                loader: container.resolve('production.package.loader')
              )
            end
            register(:hasher) {
              Package::PackageHasher.new(shell: container.resolve('shell_executor'))
            }
            register(:loader, memoize: true) do
              Common::Package::DirectoryPackageLoader.new(
                container.resolve('parameter.out.root'),
                schema_validator: container.resolve('production.schema_validator')
              )
            end

            register(:uploader) {
              Common::Remote::PackageUploader.new(s3: container.resolve('s3_client'))
            }
            register(:downloader) do
              Common::Remote::PackageDownloader.new(
                s3: container.resolve('s3_client'),
                out_dir: container.resolve('parameter.out.root'),
                package_loader: container.resolve('production.package.loader')
              )
            end

            register(:integrity_validator, memoize: true) do
              Common::Package::PackageIntegrityValidator.new(shell: container.resolve('shell_executor'))
            end
          end

          register(:schema_validator, memoize: true) { container.resolve('production.schema_validator_factory').build }
          register(:schema_validator_factory, memoize: true) {
            Common::Schema::ValidatorFactory.new(container.resolve('parameter.resources.lexicon_schema_path'))
          }
          register(:datasource_loader, memoize: true) do
            Common::Production::DatasourceLoader.new(
              shell: container.resolve('shell_executor'),
              database_factory: container.resolve('production.database.factory'),
              file_loader: container.resolve('production.file_loader'),
              database_url: container.resolve('parameter.production.database.url'),
              table_locker: container.resolve('production.table_locker'),
              psql: container.resolve('psql')
            )
          end
          register(:table_locker, memoize: true) do
            Common::Production::TableLocker.new(
              database_factory: container.resolve('production.database.factory'),
              database_url: container.resolve('parameter.production.database.url'),
            )
          end
          register(:database, memoize: true) {
            container.resolve('database.factory')
                     .new_instance(url: container.resolve('parameter.production.database.url'))
          }
          register(:file_loader, memoize: true) do
            Common::Production::FileLoader.new(
              shell: container.resolve('shell_executor'),
              database_url: container.resolve('parameter.production.database.url')
            )
          end
        end

        container.register(:roo_loader, memoize: true) { Loader::Roo.new(csv_loader: container.resolve(:csv_loader)) }

        container.register(:shell_executor, memoize: true) { Common::ShellExecutor.new }
        container.register(:shp_loader, memoize: true) do
          Loader::Shp.new(db_url: container.resolve('parameter.database.url'), executor: container.resolve('shell_executor'))
        end

        container.register(:version) { File.read(container.resolve('parameter.version.file')).strip }
        container.namespace :version do
          register(:bumper) { VersionBumper.new(version: container.resolve(:version), file: container.resolve('parameter.version.file')) }
        end
      end

      def register_datasources(container)
        Datasources.constants
                   .map { |c| Datasources.const_get(c) }
                   .reject { |c| c == Datasources::Base }
                   .select { |c| c.ancestors.include? Datasources::Base }
                   .each { |c| register_datasource(container, c) }
      end

      def register_datasource(container, klass)
        container.resolve('datasource.register') << klass
      end
  end
end
