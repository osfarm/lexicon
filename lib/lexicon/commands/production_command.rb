# frozen_string_literal: true

require 'yaml'

module Lexicon
  module Commands
      class ProductionCommand < ContainerAwareCommand
        include Lexicon::Common::Mixin::SchemaNamer

        desc 'loadable', 'List all available loadable versions'

        def loadable
          available_packages.each do |package|
            puts package.version.to_s.green
            _, invalid = package.file_sets
                                    .sort_by(&:name)
                                    .partition { |fs| valid_file_set?(fs) }

            if invalid.empty?
              puts '  -> All OK'.green
            else
              puts "  Data missing for #{invalid.size} datasource(s):"
              invalid.each {|ds| puts "  -> #{ds.name.yellow}"}
            end
          end
        end

        desc 'config', 'Display production config information'

        def config
          puts <<~TEXT
            Version dir: #{container.parameter('lexicon.common.package_dir')}
            Prod database URL: #{container.parameter('lexicon.common.production.database.url')}
          TEXT
        end

        desc 'load <VERSION>', 'Load a package into the production database'
        option :validate, type: :boolean, default: true
        option :datasources, type: :array, default: []
        option :without, type: :array, default: []

        def load(pkg_name)
          # @type [Production::DatasourceLoader] datasource_loader
          datasource_loader = get(Lexicon::Common::Production::DatasourceLoader)
          # @type [Package::PackageIntegrityValidator] integrity_validator
          integrity_validator = get(Lexicon::Common::Package::PackageIntegrityValidator)
          # @type [Package::DirectoryPackageLoader] package_loader
          package_loader = get(Lexicon::Common::Package::DirectoryPackageLoader)

          validate = options.fetch(:validate)
          names = options.fetch(:datasources, [])
          without = options.fetch(:without, [])
          package = package_loader.load_package(pkg_name)

          if package.nil?
            puts '[ NOK ] Did not find any package to load'.red
            exit 1
          elsif package.nil?
            puts "[ NOK ] No Package found for version #{version}".red
            exit 1
          elsif !validate || integrity_validator.valid?(package)
            datasource_loader.load_package(package, only: (names.empty? ? nil : names), without: without)
          else
            puts "[ NOK ] Lexicon package #{package.version} is corrupted".red
            exit 1
          end
        end

        desc 'versions', 'List versions available on the server'

        def versions
          puts "Lexicon is #{enabled? ? 'ENABLED'.green + " (#{enabled_version.to_s.yellow})" : 'DISABLED'.red}"

          available = loaded_versions
          if available.empty?
            puts 'No other versions are loaded'
          else
            puts 'Available loaded versions are:'
            loaded_versions
              .each { |e| puts " - #{e}" }
          end
        end

        desc 'disable', 'Disable the lexicon'

        def disable
          if enabled? && !(version = enabled_version).nil?
            puts "Disabling version #{version.to_s.yellow}"
            do_disable
            puts '[  OK ] Done'.green
          else
            puts 'Lexicon is not enabled'.red
          end
        end

        desc 'enable [version]', 'Enable the lexicon'

        def enable(version = nil)
          if enabled?
            puts 'Disabling current version'
            do_disable
          end

          semver = if version.nil?
                     loaded_versions.max
                   else
                     Semantic::Version.new(version)
                   end

          puts "Enabling version #{semver.to_s.yellow}"

          do_enable(semver)

          puts '[  OK ] Done'.green
        end

        desc 'delete', 'Deletes a loaded version of the lexicon'

        def delete(version)
          semver = Semantic::Version.new(version)

          if loaded_versions.include?(semver)
            production_database
              .query("DROP SCHEMA \"#{version_to_schema(semver)}\" CASCADE")

            puts '[  OK ] '.green + "The version #{semver} has been deleted."
          else
            puts '[ NOK ] '.red + "The version #{semver.to_s.yellow} is not loaded or is enabled."
            exit 1
          end
        end

        private

          # @param [Object] fs
          # @return [Boolean]
          def valid_file_set?(fs)
            if fs.is_a?(Common::Package::V2::SourceFileSet)
              fs.tables.any?
            elsif fs.is_a?(Common::Package::V1::SourceFileSet)
              !fs.data_path.nil?
            else
              false
            end
          end

          def production_database
            get(Lexicon::Cli::Extension::ProductionExtension::DATABASE)
          end

          # @return [Array<Package::Package>]
          def available_packages
            # @type [Package::DirectoryPackageLoader] package_loader
            package_loader = get(Lexicon::Common::Package::DirectoryPackageLoader)

            if package_loader.root_dir.exist?
              package_loader.root_dir
                            .children
                            .select(&:directory?)
                            .map { |dir| package_loader.load_package(dir.basename.to_s) }
                            .compact
                            .sort { |a, b| a.version <=> b.version }
            else
              []
            end
          end

          # @param [Semantic::Version] version
          def do_enable(version)
            production_database.query <<~SQL
              BEGIN;
                ALTER SCHEMA "lexicon__#{version.to_s.gsub('.', '_')}" RENAME TO "lexicon";
                CREATE TABLE "lexicon"."version" ("version" VARCHAR);
                INSERT INTO "lexicon"."version" VALUES ('#{version}');
              COMMIT;
            SQL
          end

          def do_disable
            version = enabled_version
            raise StandardError.new('No version table present, cannot continue automatically') if version.nil?

            production_database.query <<~SQL
              BEGIN;
                DROP TABLE "lexicon"."version";
                ALTER SCHEMA "lexicon" RENAME TO "#{version_to_schema(version)}";
              COMMIT;
            SQL
          end

          # @return [Array<Semantic::Version>]
          def loaded_versions
            disabled = production_database
                         .query("SELECT nspname FROM pg_catalog.pg_namespace WHERE nspname LIKE 'lexicon__%';")
                         .to_a
                         .map { |name| schema_to_version(name.fetch('nspname')) }

            enabled = enabled_version

            if enabled.nil?
              disabled
            else
              [*disabled, enabled].sort
            end
          end

          # @return [Semantic::Version, nil]
          def enabled_version
            if version_table_present?
              Semantic::Version.new(
                production_database
                  .query('SELECT version FROM lexicon.version LIMIT 1')
                  .to_a.first
                  .fetch('version')
              )
            else
              nil
            end
          end

          # @param [String, nil] version
          # @return [Semantic::Version]
          def as_version(version, &block)
            if version.nil?
              block.call
            else
              Semantic::Version.new(version)
            end
          end

          def version_table_present?
            production_database
              .query("SELECT count(*) AS presence FROM information_schema.tables WHERE table_schema = 'lexicon' AND table_name = 'version'")
              .to_a.first
              .fetch('presence').to_i.positive?
          end

          def enabled?
            production_database
              .query("SELECT count(nspname) AS presence FROM pg_catalog.pg_namespace WHERE nspname = 'lexicon'")
              .to_a.first
              .fetch('presence').to_i.positive?
          end
    end
  end
end
