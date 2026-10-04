# frozen_string_literal: true

require 'test_helper'

module Lexicon
  module Contribution
    class CheckerTest < Minitest::Test
      def test_a_complete_open_datasource_has_nothing_to_report
        assert_empty static(datasource)
      end

      def test_description_and_credits_are_required
        messages = static(datasource(description: nil, credits: nil)).map(&:message)

        assert_includes messages, 'no description'
        assert(messages.any? { |message| message.start_with?('no credits') })
      end

      def test_credits_need_a_provider_a_licence_and_a_real_date
        messages = static(datasource(credits: { provider: '', licence: '', updated_at: 'last spring' })).map(&:message)

        assert_includes messages, 'credits without provider'
        assert_includes messages, 'credits without licence'
        assert(messages.any? { |message| message.include?('invalid date') })
      end

      def test_a_non_commercial_licence_must_be_reserved
        open = static(datasource(credits: { licence: 'CC BY-NC-SA 4.0' }))
        reserved = static(datasource(credits: { licence: 'CC BY-NC-SA 4.0' }, scope: 'members'))

        assert_equal [:error], open.map(&:level)
        assert_match(/not an open licence/, open.first.message)
        assert_empty reserved
      end

      def test_a_licence_exception_states_why_a_non_open_licence_is_published
        findings = static(datasource(credits: { licence: 'CC BY-NC-SA 4.0' }, licence_exception: 'public at its source'))

        assert_equal [:warning], findings.map(&:level)
        assert_match(/published openly: public at its source/, findings.first.message)
      end

      def test_an_unknown_licence_is_refused_and_a_share_alike_one_is_flagged
        assert_equal [:error], static(datasource(credits: { licence: 'Tous droits réservés' })).map(&:level)
        assert_equal [:warning], static(datasource(credits: { licence: 'ODbL 1.0' })).map(&:level)
        assert_empty static(datasource(credits: { licence: 'CC-BY 4.0' }))
      end

      def test_columns_that_look_personal_must_be_removed_or_justified
        sql = 'CREATE TABLE people (id varchar PRIMARY KEY, first_name character varying, email text, city varchar);'
        refused = static(datasource(sql: sql))
        justified = static(datasource(sql: sql, personal_data: 'legal entities only'))

        assert_equal [:error], refused.map(&:level)
        assert_match(/t\.first_name, t\.email/, refused.first.message)
        assert_equal [:warning], justified.map(&:level)
        assert_match(/legal entities only/, justified.first.message)
      end

      def test_usual_abbreviations_of_the_open_licence_are_recognised
        assert_empty static(datasource(credits: { licence: 'LO2.0' }))
        assert_empty static(datasource(credits: { licence: 'LOOL' }))
      end

      def test_personal_words_are_found_inside_longer_column_names
        sql = 'CREATE TABLE t (id varchar PRIMARY KEY, beneficiary_firstname varchar, company_name varchar, renamed varchar);'

        assert_match(/t\.beneficiary_firstname\. /, static(datasource(sql: sql)).first.message)
      end

      def test_known_issues_of_a_tolerated_datasource_do_not_block
        klass = datasource(credits: { licence: 'proprietary' })
        definition = Struct.new(:definitions).new([Struct.new(:name, :sql).new('t', klass.sql)])
        checker = Checker.new(datasources: { 'demo' => klass }, definitions: { 'demo' => definition }, tolerated: ['demo'])

        findings = checker.static('demo')

        assert_equal [:warning], findings.map(&:level)
        assert_match(/\Aknown issue: licence 'proprietary'/, findings.first.message)
      end

      def test_a_packaged_datasource_declares_tables
        assert_equal ['declares no table (table_definitions)'], static(datasource(sql: nil)).map(&:message)
        assert_empty static(datasource(sql: nil, packaged: false))
      end

      def test_dependencies_must_exist
        messages = static(datasource(dependencies: %w[nothing demo])).map(&:message)

        assert_includes messages, 'depends on unknown datasources: nothing'
        assert_includes messages, 'depends on itself'
      end

      def test_translation_prefixes_belong_to_one_datasource
        other = datasource(translations: ['units'], packaged: false)
        checker = Checker.new(datasources: { 'demo' => datasource(translations: ['units'], packaged: false), 'other' => other }, definitions: {})

        assert_equal ["translation prefix 'units' is also declared by other"], checker.static('demo').map(&:message)
      end

      def test_pivots_are_declared_on_tables_of_the_datasource
        findings = static(datasource(pivots: [{ key: 'commune', table: 'elsewhere', column: 'code' }]))

        assert_match(/declared on elsewhere/, findings.first.message)
      end

      def test_built_data_must_fill_tables_match_pivots_and_keep_its_volume
        checker = Checker.new(datasources: { 'demo' => datasource }, definitions: {})
        previous = Struct.new(:tables).new([{ name: 't', rows: 1000 }, { name: 'u', rows: 10 }])
        pivots = [
          { key: 'commune', table: 't', column: 'code', minimum: 0.95, values: 100, matched: 80, rate: 0.8 },
          { key: 'siren', table: 't', column: 'siren', values: 100, matched: 10, rate: 0.1 },
          { key: 'taxon', table: 't', column: 'taxon', values: 0, matched: 0, rate: nil }
        ]

        findings = checker.data('demo', pivots: pivots, rows: { 't' => 600, 'u' => 0, 'v' => 5 }, previous: previous)

        assert_equal [
          [:error, 'u is empty'],
          [:error, 't.code → commune: 80.0 % of values match, 95.0 % required'],
          [:warning, 't.taxon → taxon: match rate not measurable (no value, or reference not built)'],
          [:error, 't: 600 rows, 1000 in the latest package'],
          [:error, 'u: 0 rows, 10 in the latest package']
        ], findings.map { |finding| [finding.level, finding.message] }
        assert_empty checker.data('demo', pivots: [], rows: { 't' => 900 }, previous: previous)
      end

      def test_scaffold_gives_a_datasource_that_passes_once_filled
        source = Scaffold.new.datasource('soil_moisture')

        assert_includes source, 'class SoilMoisture < Base'
        assert_includes source, 'builder.table(:registered_soil_moisture'
        assert_raises(ArgumentError) { Scaffold.new.datasource('Soil Moisture') }
        RubyVM::InstructionSequence.compile(source).eval
        assert_equal 'soil_moisture', Datasources::SoilMoisture.datasource_name
        assert_equal 1, Datasources::SoilMoisture.schema_revision
      ensure
        Datasources.send(:remove_const, :SoilMoisture) if Datasources.const_defined?(:SoilMoisture)
      end

      private

        Credit = Struct.new(:provider, :licence, :updated_at, keyword_init: true)

        def static(klass)
          table = Struct.new(:name, :sql)
          definition = klass.sql.nil? ? nil : Struct.new(:definitions).new([table.new('t', klass.sql)])

          Checker.new(datasources: { 'demo' => klass }, definitions: { 'demo' => definition }.compact).static('demo')
        end

        def datasource(description: 'A demo', credits: {}, scope: 'open', packaged: true, personal_data: nil, licence_exception: nil,
                       dependencies: [], translations: [], pivots: [], sql: 'CREATE TABLE t (id varchar PRIMARY KEY, name varchar);')
          credit = credits && Credit.new(**{ provider: 'OSFarm', licence: 'Licence Ouverte 2.0', updated_at: '2026-10-04' }.merge(credits))

          Struct.new(:description, :get_credits, :scope, :packaged?, :personal_data, :licence_exception, :get_dependencies,
                     :get_translation_prefixes, :get_pivots, :sql)
                .new(description, [credit].compact, scope, packaged, personal_data, licence_exception, dependencies,
                     translations, pivots, sql)
        end
    end
  end
end
