# frozen_string_literal: true

using Corindon::Result::Ext

module Lexicon
  module Common
    module Production
      class DatasourceLoader
        include Mixin::LoggerAware
        include Mixin::SchemaNamer

        # @param [ShellExecutor] shell
        # @param [Database::Factory] database_factory
        # @param [FileLoader] file_loader
        # @param [String] database_url
        # @param [TableLocker] table_locker
        # @param [Psql] psql
        def initialize(shell:, database_factory:, file_loader:, database_url:, table_locker:, psql:)
          @shell = shell
          @database_factory = database_factory
          @file_loader = file_loader
          @database_url = database_url
          @table_locker = table_locker
          @psql = psql
        end

        # @param [Package::Package] package
        # @param [Array<String>, nil] only
        #   If nil, all datasets are loaded.
        #   If present, only listed datasets are loaded.
        #   Structures are ALWAYS loaded
        # @param [Array<String>] without
        def load_package(package, only: nil, without: [])
          case package.schema_version
          when 1
            load_v1(package, only: only, without: without)
          when 2
            load_v2(package, only: only, without: without)
          else
            log("Schema version #{package.schema_version} is not supported")
          end
        end

        private

          # @param [Package::V1::Package] package
          def load_v1(package, only: nil, without: [])
            file_sets = filter_file_sets(package.file_sets, only: only, without: without)
                          .unwrap!
                          .select(&:data_path)

            load_structure_files(
              package.files.select(&:structure?).map(&:path),
              schema: version_to_schema(package.version),
              dir: package.dir
            )

            remaining = ::Concurrent::Set.new(file_sets.map(&:name))

            file_sets.map do |fs|
              Thread.new do
                file_loader.load_file(package.data_path(fs))
                remaining.delete(fs.name)

                puts '[  OK ] '.green + fs.name.yellow + ", #{remaining_message(remaining)}"
              end
            end.each(&:join)

            table_locker.lock_tables(package: package, tables: package.file_sets.flat_map(&:tables))
          end

          def remaining_message(remaining)
            if remaining.size.zero?
              'All done!'
            elsif remaining.size > 5
              "#{remaining.size} remaining"
            else
              "Remaining: #{remaining.to_a.sort.join(', ')}"
            end
          end

          # @param [Package::V2::Package] package
          # @param [Array<String>, nil] only
          # @param [Array<String>] without
          def load_v2(package, only: nil, without: [])
            file_sets = filter_file_sets(package.file_sets, only: only, without: without)
                          .unwrap!
                          .select { |fs| fs.tables.any? }

            schema = version_to_schema(package.version)

            load_structure_files(package.files.select(&:structure?).map(&:path), schema: schema, dir: package.dir)

            remaining = ::Concurrent::Set.new(file_sets.flat_map{|fs| fs.tables.values.flatten(1) })

            threads = file_sets.flat_map do |fs|
              fs.tables.flat_map do |name, files|
                files.map do |file|
                  Thread.new do
                    load_csv(package.data_dir.join(file), into: name, schema: schema)
                    remaining.delete(file)

                    puts '[  OK ] '.green + file.to_s.yellow + ", #{remaining_message(remaining)}"
                  end
                end
              end
            end

            threads.each(&:join)
          end

          # @param [Array<Package::Mixin::Nameable>] file_sets
          # @param [Array<String>, nil] only
          # @param [Array<String>] without
          # @return [Corindon::Result::Result]
          def filter_file_sets(file_sets, only:, without:)
            sets = if only.nil?
                     file_sets
                   else
                     sets_by_name = file_sets.map { |fs| [fs.name, fs] }.to_h

                     missing, present = only.map { |name| [name, sets_by_name.fetch(name, nil)] }
                                            .partition { |(_name, value)| value.nil? }

                     if missing.any?
                       puts "[ NOK ] Datasources #{missing.map(&:first).join(', ')} don't exist!"

                       return Failure(StandardError.new("Datasources #{missing.map(&:first).join(', ')} don't exist!"))
                     end

                     present.map(&:second)
                            .select(&:data_path)
                   end

            Success(sets.reject { |fs| without.include?(fs.name) })
          end

          # @return [Database::Factory]
          attr_reader :database_factory
          # @return [ShellExecutor]
          attr_reader :shell
          # @return [FileLoader]
          attr_reader :file_loader
          # @return [String]
          attr_reader :database_url
          # @return [TableLocker]
          attr_reader :table_locker
          # @return [Psql]
          attr_reader :psql

          # @param [Pathname] file
          # @param [String] into
          # @param [String] schema
          def load_csv(file, into:, schema:)
            psql.execute_raw(<<~SQL)
              \\copy "#{schema}"."#{into}" FROM PROGRAM 'zcat < #{file}' WITH csv
            SQL
          end

          def load_structure_files(files, schema:, dir:)
            database = database_factory.new_instance(url: database_url)
            database.prepend_search_path(schema) do
              files.each do |file|
                database.query(dir.join(file).read)
              end
            end
          end
      end
    end
  end
end
