# frozen_string_literal: true

require 'test_helper'
require 'zlib'
require 'digest'

module Lexicon
  module Server
    # Runs against a scratch database created on the development server.
    class LoaderTest < Minitest::Test
      DATABASE = 'lexicon_loader_test'

      def setup
        admin.exec(%(DROP DATABASE IF EXISTS "#{DATABASE}"))
        admin.exec(%(CREATE DATABASE "#{DATABASE}"))
        @connection = PG.connect(url(DATABASE))
        @connection.exec('SET client_min_messages TO WARNING; CREATE SCHEMA postgis')
        @root = Pathname.new(Dir.mktmpdir)
        @repository = Packaging::Repository.new(@root)
        @meta = Meta.new(@connection)
        @swapper = swapper
        @loader = loader(@swapper)
      end

      def teardown
        @connection&.close
        admin.exec(%(DROP DATABASE IF EXISTS "#{DATABASE}"))
        admin.close
        FileUtils.rm_rf(@root)
      end

      def test_first_load_puts_tables_data_and_indexes_in_service
        package('units', '2026.10.01.1', units: [%w[kilogram kg], %w[liter l]])

        outcome = @loader.sync(['units']).first

        assert_equal :swapped, outcome.state
        assert_nil outcome.previous
        assert_equal [%w[kilogram kg], %w[liter l]], rows('SELECT reference_name, symbol FROM lexicon.units ORDER BY 1')
        assert_equal ['units_pkey', 'units_symbol'], rows("SELECT indexname FROM pg_indexes WHERE schemaname = 'lexicon' ORDER BY 1").flatten
        assert_equal '2026.10.01.1', @meta.installed('units').version
        assert_equal ['units'], @meta.tables_of('units')
        assert_empty staged_tables
        assert_equal 'swapped', @meta.recent_loads.first['state']
      end

      def test_new_version_replaces_the_one_in_service
        package('units', '2026.10.01.1', units: [%w[kilogram kg]])
        @loader.sync(['units'])
        package('units', '2026.10.02.1', units: [%w[kilogram kg], %w[ton t]])

        outcome = @loader.sync(['units']).first

        assert_equal :swapped, outcome.state
        assert_equal '2026.10.01.1', outcome.previous
        assert_equal 2, count('lexicon.units')
        assert_equal '2026.10.02.1', @meta.installed('units').version
      end

      def test_version_already_in_service_is_not_reloaded
        package('units', '2026.10.01.1', units: [%w[kilogram kg]])
        @loader.sync(['units'])

        assert_equal :up_to_date, @loader.sync(['units']).first.state
        assert_equal 1, @meta.recent_loads.size
        assert_equal :swapped, @loader.sync(['units'], force: true).first.state
      end

      def test_index_designates_the_version_to_serve
        package('units', '2026.10.01.1', units: [%w[kilogram kg]])
        package('units', '2026.10.02.1', units: [%w[kilogram kg], %w[ton t]])
        @root.join('index.json').write({ datasources: { units: { current: '2026.10.01.1' } } }.to_json)

        assert_equal '2026.10.01.1', @loader.sync.first.version
        assert_equal '2026.10.02.1', @loader.sync(['units@2026.10.02.1']).first.version
      end

      def test_corrupted_file_leaves_the_version_in_service
        package('units', '2026.10.01.1', units: [%w[kilogram kg]])
        @loader.sync(['units'])
        dir = package('units', '2026.10.02.1', units: [%w[kilogram kg], %w[ton t]])
        dir.join('data/units_0.csv.gz').write('garbage')

        outcome = @loader.sync(['units']).first

        assert_equal :failed, outcome.state
        assert_match(/corrupted/, outcome.reasons.first)
        assert_equal '2026.10.01.1', @meta.installed('units').version
        assert_equal 1, count('lexicon.units')
        assert_equal 'failed', @meta.recent_loads.first['state']
      end

      def test_row_count_differing_from_the_manifest_is_refused
        package('units', '2026.10.01.1', units: [%w[kilogram kg]])
        @loader.sync(['units'])
        package('units', '2026.10.02.1', { units: [%w[kilogram kg], %w[ton t]] }, declared_rows: { units: 5 })

        outcome = @loader.sync(['units']).first

        assert_equal :failed, outcome.state
        assert_match(/2 rows loaded, 5 expected/, outcome.reasons.first)
        assert_equal 1, count('lexicon.units')
        assert_empty staged_tables
      end

      def test_drop_of_volume_needs_force
        package('units', '2026.10.01.1', units: Array.new(10) { |i| ["unit#{i}", "u#{i}"] })
        @loader.sync(['units'])
        package('units', '2026.10.02.1', units: [%w[unit0 u0]])

        outcome = @loader.sync(['units']).first

        assert_equal :failed, outcome.state
        assert_match(/1 rows, 10 in service/, outcome.reasons.first)
        assert_equal 10, count('lexicon.units')
        assert_equal :swapped, @loader.sync(['units'], force: true).first.state
        assert_equal 1, count('lexicon.units')
      end

      def test_referenced_package_is_loaded_first_and_foreign_keys_are_created
        package('units', '2026.10.01.1', units: [%w[kilogram kg]])
        package('productions', '2026.10.01.1', { productions: [%w[wheat kilogram]] }, references: 'units')

        outcomes = @loader.sync(%w[productions units])

        assert_equal %w[units productions], outcomes.map(&:name)
        assert_equal [:swapped, :swapped], outcomes.map(&:state)
        assert_equal 1, foreign_keys.size
      end

      def test_package_referencing_a_package_not_in_service_is_refused
        package('productions', '2026.10.01.1', { productions: [%w[wheat kilogram]] }, references: 'units')

        outcome = @loader.sync(['productions']).first

        assert_equal :failed, outcome.state
        assert_match(/units it references is not in service/, outcome.reasons.first)
      end

      def test_replacing_a_referenced_package_keeps_inbound_foreign_keys
        package('units', '2026.10.01.1', units: [%w[kilogram kg]])
        package('productions', '2026.10.01.1', { productions: [%w[wheat kilogram]] }, references: 'units')
        @loader.sync
        before = foreign_keys
        package('units', '2026.10.02.1', units: [%w[kilogram kg], %w[ton t]])

        outcome = @loader.sync(['units']).first

        assert_equal :swapped, outcome.state
        assert_equal before, foreign_keys
        assert_raises(PG::ForeignKeyViolation) { @connection.exec("INSERT INTO lexicon.productions VALUES ('rye', 'nothing')") }
      end

      def test_replacing_a_referenced_package_is_refused_when_it_orphans_rows
        package('units', '2026.10.01.1', units: [%w[kilogram kg], %w[liter l]])
        package('productions', '2026.10.01.1', { productions: [%w[wheat kilogram]] }, references: 'units')
        @loader.sync
        package('units', '2026.10.02.1', units: [%w[liter l], %w[ton t]])

        outcome = @loader.sync(['units']).first

        assert_equal :failed, outcome.state
        assert_equal ['productions.unit has values missing from units.reference_name: kilogram'], outcome.reasons
        assert_equal '2026.10.01.1', @meta.installed('units').version
        assert_equal [%w[kilogram], %w[liter]], rows('SELECT reference_name FROM lexicon.units ORDER BY 1')
        assert_equal 1, foreign_keys.size
        assert_empty staged_tables
      end

      def test_table_removed_from_a_package_is_dropped
        package('units', '2026.10.01.1', units: [%w[kilogram kg]], dimensions: [%w[mass m]])
        @loader.sync
        package('units', '2026.10.02.1', units: [%w[kilogram kg]])

        @loader.sync

        assert_equal ['units'], rows("SELECT tablename FROM pg_tables WHERE schemaname = 'lexicon'").flatten
        assert_equal ['units'], @meta.tables_of('units')
      end

      def test_table_owned_by_another_package_is_refused
        package('units', '2026.10.01.1', units: [%w[kilogram kg]])
        package('other', '2026.10.01.1', units: [%w[kilogram kg]])

        outcomes = @loader.sync(%w[units other])

        assert_equal [:swapped, :failed], outcomes.map(&:state)
        assert_match(/units already belongs to the package units/, outcomes.last.reasons.first)
      end

      def test_view_depending_on_a_table_blocks_its_replacement
        package('units', '2026.10.01.1', units: [%w[kilogram kg]])
        @loader.sync
        @connection.exec('CREATE VIEW public.unit_names AS SELECT reference_name FROM lexicon.units')
        package('units', '2026.10.02.1', units: [%w[kilogram kg], %w[ton t]])

        outcome = @loader.sync.first

        assert_equal :failed, outcome.state
        assert_match(/view public.unit_names depends on units/, outcome.reasons.first)
        assert_equal 1, count('public.unit_names')
      end

      def test_locked_table_makes_the_swap_fail_without_effect
        package('units', '2026.10.01.1', units: [%w[kilogram kg]])
        @loader.sync
        package('units', '2026.10.02.1', units: [%w[kilogram kg], %w[ton t]])
        reader = PG.connect(url(DATABASE))
        reader.exec('BEGIN; LOCK TABLE lexicon.units IN ACCESS SHARE MODE')
        loader = loader(swapper(retry_delay: 0.05, lock_timeout: '100ms'))

        outcome = loader.sync.first

        assert_equal :failed, outcome.state
        assert_match(/locks not obtained/, outcome.reasons.first)
        assert_equal '2026.10.01.1', @meta.installed('units').version
        reader.exec('ROLLBACK')
        assert_equal :swapped, loader.sync.first.state
      ensure
        reader&.close
      end

      def test_second_loader_is_refused_while_one_runs
        other = PG.connect(url(DATABASE))
        other.exec_params('SELECT pg_advisory_lock($1)', [Loader::ADVISORY_LOCK])
        package('units', '2026.10.01.1', units: [%w[kilogram kg]])

        error = assert_raises(LoadFailure) { @loader.sync }

        assert_match(/another load is running/, error.message)
      ensure
        other&.close
      end

      def test_reference_to_a_missing_value_is_refused_with_the_values
        package('units', '2026.10.01.1', units: [%w[kilogram kg]])
        package('productions', '2026.10.01.1', { productions: [%w[wheat kilogram], %w[milk liter], %w[wood stere]] }, references: 'units')

        outcomes = @loader.sync

        assert_equal [:swapped, :failed], outcomes.map(&:state)
        assert_equal ['productions.unit has values missing from units.reference_name: liter, stere'], outcomes.last.reasons
        assert_empty staged_tables
      end

      def test_swap_itself_refuses_a_broken_foreign_key
        package('units', '2026.10.01.1', units: [%w[kilogram kg]])
        package('productions', '2026.10.01.1', { productions: [%w[wheat kilogram]] }, references: 'units')
        @loader.sync
        package('units', '2026.10.02.1', units: [%w[ton t]])
        manifest = @repository.manifest('units', '2026.10.02.1')
        Stager.new(@connection).stage(@repository.package_dir('units', '2026.10.02.1'), manifest)

        error = assert_raises(LoadFailure) { @swapper.swap([manifest], previous_tables: ['units']) }

        assert_match(/foreign key does not hold/, error.message)
        assert_equal [%w[kilogram]], rows('SELECT reference_name FROM lexicon.units')
      end

      def test_packages_depending_on_each_other_are_replaced_together
        package('units', '2026.10.01.1', units: [%w[kilogram kg]])
        package('productions', '2026.10.01.1', { productions: [%w[wheat kilogram]] }, references: 'units')
        @loader.sync
        package('units', '2026.10.02.1', units: [%w[ton t]])
        package('productions', '2026.10.02.1', { productions: [%w[wheat ton]] }, references: 'units')

        assert_equal :failed, @loader.sync(['units']).first.state
        outcomes = @loader.sync(%w[units productions], together: true)

        assert_equal [:swapped, :swapped], outcomes.map(&:state)
        assert_equal [%w[wheat ton]], rows('SELECT * FROM lexicon.productions')
        assert_equal 1, foreign_keys.size
      end

      def test_packages_loaded_together_are_all_refused_when_one_fails
        package('units', '2026.10.01.1', units: [%w[kilogram kg]])
        package('productions', '2026.10.01.1', { productions: [%w[wheat kilogram]] }, references: 'units')
        @loader.sync
        package('units', '2026.10.02.1', units: [%w[kilogram kg], %w[ton t]])
        package('productions', '2026.10.02.1', { productions: [%w[wheat stere]] }, references: 'units')

        outcomes = @loader.sync([], together: true)

        assert_equal [:failed, :failed], outcomes.map(&:state)
        assert_equal '2026.10.01.1', @meta.installed('units').version
        assert_equal 1, count('lexicon.units')
        assert_empty staged_tables
      end

      def test_package_built_against_another_version_of_its_dependency_is_stale
        package('units', '2026.10.01.1', units: [%w[kilogram kg]])
        package('productions', '2026.10.01.1', { productions: [%w[wheat kilogram]] }, references: 'units', built_against: '2026.10.01.1')
        @loader.sync
        refute @meta.installed('productions').stale

        package('units', '2026.10.02.1', units: [%w[kilogram kg], %w[ton t]])
        @loader.sync
        assert @meta.installed('productions').stale

        package('productions', '2026.10.02.1', { productions: [%w[wheat ton]] }, references: 'units', built_against: '2026.10.02.1')
        @loader.sync
        refute @meta.installed('productions').stale
      end

      def test_translations_of_each_package_are_served_as_one_view
        package('units', '2026.10.01.1', { units: [%w[kilogram kg]], units__translations: [%w[units_kilogram Kilogramme Kilogram]] }, roles: { units__translations: 'translations' })
        package('taxa', '2026.10.01.1', { taxa: [%w[bos b]], taxa__translations: [%w[taxonomy_bos Bovin Cattle]] }, roles: { taxa__translations: 'translations' })
        @loader.sync
        assert_equal [%w[taxonomy_bos Bovin Cattle], %w[units_kilogram Kilogramme Kilogram]], rows('SELECT * FROM lexicon.master_translations ORDER BY 1')

        package('units', '2026.10.02.1', { units: [%w[kilogram kg]], units__translations: [%w[units_kilogram Kilo Kilo], %w[units_ton Tonne Ton]] }, roles: { units__translations: 'translations' })
        assert_equal :swapped, @loader.sync(['units']).first.state

        assert_equal [%w[taxonomy_bos Bovin Cattle], %w[units_kilogram Kilo Kilo], %w[units_ton Tonne Ton]], rows('SELECT * FROM lexicon.master_translations ORDER BY 1')
      end

      def test_translations_view_exists_without_any_translation
        package('units', '2026.10.01.1', units: [%w[kilogram kg]])
        @loader.sync

        assert_equal 0, count('lexicon.master_translations')
      end

      def test_credits_come_from_the_packages_in_service
        package('units', '2026.10.01.1', { units: [%w[kilogram kg]] }, credits: [{ name: 'Units', url: 'https://example.org', provider: 'Ekylibre', licence: 'CC-BY-SA 4.0', licence_url: nil, updated_at: '2022-02-23' }])
        @loader.sync

        assert_equal [['units', 'Units', 'Ekylibre', '2022-02-23']], rows("SELECT datasource, name, provider, updated_at::date::text FROM lexicon.datasource_credits")
      end

      def test_status_file_reports_what_is_in_service_and_the_last_failures
        package('units', '2026.10.01.1', units: [%w[kilogram kg]])
        @loader.sync
        package('units', '2026.10.02.1', { units: [%w[kilogram kg]] }, declared_rows: { units: 9 })
        @loader.sync

        StatusFile.new(repository: @repository, meta: @meta).write
        status = JSON.parse(@root.join('status.json').read)

        assert_equal '2026.10.01.1', status.dig('packages', 'units', 'version')
        assert_equal false, status.dig('packages', 'units', 'stale')
        assert_equal ['units'], status['last_failures'].map { |failure| failure['name'] }
        assert_match(/1 rows loaded, 9 expected/, status['last_failures'].first['reasons'].first)
        refute @root.join('.status.json.tmp').exist?
        assert_equal ['units'], @repository.names
      end

      def test_rollback_puts_the_previous_version_back
        package('units', '2026.10.01.1', units: Array.new(10) { |i| ["unit#{i}", "u#{i}"] })
        @loader.sync
        package('units', '2026.10.02.1', units: [%w[unit0 u0]])
        @loader.sync(['units'], force: true)

        outcome = @loader.rollback('units')

        assert_equal :swapped, outcome.state
        assert_equal '2026.10.01.1', @meta.installed('units').version
        assert_equal 10, count('lexicon.units')
        assert_equal '2026.10.01.1', @repository.current('units')
        assert_equal %w[swapped rolled_back swapped], @meta.recent_loads.map { |load| load['state'] }
        assert_equal :up_to_date, @loader.sync.first.state
      end

      def test_rollback_needs_a_previous_version_still_in_the_repository
        package('units', '2026.10.01.1', units: [%w[kilogram kg]])
        @loader.sync
        assert_match(/did not replace any version/, assert_raises(LoadFailure) { @loader.rollback('units') }.message)

        package('units', '2026.10.02.1', units: [%w[kilogram kg]])
        @loader.sync
        FileUtils.rm_rf(@repository.package_dir('units', '2026.10.01.1'))
        assert_match(/no longer in/, assert_raises(LoadFailure) { @loader.rollback('units') }.message)
        assert_match(/not in service/, assert_raises(LoadFailure) { @loader.rollback('nothing') }.message)
      end

      def test_prune_removes_old_versions_and_packages_gone_from_the_repository
        %w[2026.10.01.1 2026.10.02.1 2026.10.03.1 2026.10.04.1].each { |version| package('units', version, units: [%w[kilogram kg]]) }
        package('gone', '2026.10.01.1', gone: [%w[a b]], gone__translations: [%w[gone_a A A]], roles: { gone__translations: 'translations' })
        @loader.sync(['units@2026.10.02.1', 'gone'])
        FileUtils.rm_rf(@root.join('gone'))
        pruner = Pruner.new(
          repository: @repository, retention: Packaging::Retention.new(default: 1), meta: @meta, swapper: @swapper
        )

        plan = pruner.plan

        assert_equal [%w[units 2026.10.01.1], %w[units 2026.10.03.1]], plan.versions
        assert_equal ['gone'], plan.packages
        assert_equal 4, @repository.versions('units').size

        pruner.apply(plan)

        assert_equal %w[2026.10.02.1 2026.10.04.1], @repository.versions('units')
        assert_nil @meta.installed('gone')
        assert_equal ['units'], rows("SELECT tablename FROM pg_tables WHERE schemaname = 'lexicon'").flatten
        assert_equal 0, count('lexicon.master_translations')
        assert pruner.plan.empty?
      end

      private

        def swapper(**options)
          catalog = Catalog.new(@connection)

          Swapper.new(@connection, catalog: catalog, derived_views: DerivedViews.new(@connection, meta: @meta), retry_delay: 0.1, **options)
        end

        def loader(swapper)
          Loader.new(
            connection: @connection, repository: @repository, meta: @meta, stager: Stager.new(@connection),
            checker: Checker.new(@connection, meta: @meta, catalog: Catalog.new(@connection)), swapper: swapper
          )
        end

        def admin
          @admin ||= PG.connect(url(ENV.fetch('POSTGRES_DB', 'lexicon'))).tap do |connection|
            connection.exec('SET client_min_messages TO WARNING')
          end
        end

        def url(database)
          "postgres://#{ENV.fetch('POSTGRES_USER')}:#{ENV.fetch('POSTGRES_PASSWORD')}@#{ENV.fetch('POSTGRES_HOST')}:#{ENV['POSTGRES_PORT'].presence || 5432}/#{database}"
        end

        def rows(sql)
          @connection.exec(sql).values
        end

        def count(table)
          rows("SELECT count(*) FROM #{table}").first.first.to_i
        end

        def staged_tables
          rows("SELECT tablename FROM pg_tables WHERE schemaname = 'lexicon_staging'").flatten
        end

        def foreign_keys
          rows(<<~SQL)
            SELECT conrelid::regclass::text, conname, confrelid::regclass::text FROM pg_constraint
             WHERE contype = 'f' AND connamespace = 'lexicon'::regnamespace ORDER BY 1, 2
          SQL
        end

        # Writes a package whose tables all have two varchar columns, the first being the primary key.
        #
        # @param [Hash{Symbol => Array<Array<String>>}] tables rows of each table
        # @param [String, nil] references package whose first table the second column references
        # @return [Pathname]
        def package(name, version, explicit_tables = nil, declared_rows: {}, references: nil, built_against: nil, roles: {}, credits: [], **tables)
          tables = explicit_tables unless explicit_tables.nil?
          dir = @repository.package_dir(name, version)
          dir.join('data').mkpath
          columns = references ? %w[reference_name unit] : %w[reference_name symbol]

          dir.join('structure.sql').write(tables.keys.map { |table| <<~SQL }.join("\n"))
            CREATE TABLE #{table} (#{(roles[table] ? %w[id fra eng] : columns).join(' character varying, ')} character varying, PRIMARY KEY (#{roles[table] ? 'id' : columns[0]}));
          SQL
          dir.join('indexes.sql').write(tables.keys.reject { |table| roles[table] }.map { |table| "CREATE INDEX #{table}_#{columns[1]} ON #{table}(#{columns[1]});\n" }.join)

          Packaging::Manifest.new(
            name: name, version: version, schema_revision: 1, structure_hash: 'sha256:0', built_at: Time.now, tool_version: 'test',
            credits: credits,
            depends_on: references ? [{ name: references, kind: 'foreign_key', built_against: built_against }] : [],
            tables: tables.map { |table, lines| table_entry(dir, table, lines, declared_rows[table]).merge({ role: roles[table] }.compact) },
            foreign_keys: references ? [{ table: tables.keys.first.to_s, column: 'unit', references_table: references, references_column: 'reference_name' }] : []
          ).write(dir)

          dir
        end

        def table_entry(dir, table, lines, declared_rows)
          path = "data/#{table}_0.csv.gz"
          Zlib::GzipWriter.open(dir.join(path).to_s) { |gzip| lines.each { |line| gzip.write("#{line.join(',')}\n") } }

          {
            name: table.to_s, rows: declared_rows || lines.size,
            files: [{ path: path, sha256: Digest::SHA256.file(dir.join(path)).hexdigest, bytes: dir.join(path).size }]
          }
        end
    end
  end
end
