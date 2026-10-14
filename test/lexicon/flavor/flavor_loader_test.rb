# frozen_string_literal: true

require 'test_helper'

module Lexicon
  module Flavor
    class FlavorLoaderTest < Minitest::Test
      SCHEMA = Pathname.new(__dir__).join('../../../resources/flavor.schema.json').expand_path

      def setup
        @dir = Pathname.new(Dir.mktmpdir)
        @loader = FlavorLoader.new(dir: @dir, validator: Common::Schema::ValidatorFactory.new(SCHEMA).build)
      end

      def teardown
        FileUtils.rm_rf(@dir)
      end

      def test_a_tracked_flavor_names_its_datasources
        write('farm', 'tracked' => true, 'only' => %w[units prices])

        flavor = @loader.load('farm').unwrap!

        assert flavor.tracked?
        assert_equal %w[units prices], flavor.only
      end

      def test_a_flavor_is_not_tracked_unless_it_says_so
        write('light', 'without' => ['weather'])

        refute @loader.load('light').unwrap!.tracked?
      end

      def test_a_tracked_flavor_without_names_is_refused
        write('farm', 'tracked' => true)

        assert_match(/must name its datasources/, failure('farm'))
      end

      def test_a_tracked_flavor_cannot_exclude_nor_filter
        write('farm', 'tracked' => true, 'only' => ['units'], 'without' => ['weather'])
        write('field', 'tracked' => true, 'only' => ['units'], 'datasources' => { 'units' => { 'master_units' => { 'filter' => 'WHERE false' } } })

        assert_match(/cannot exclude/, failure('farm'))
        assert_match(/cannot filter/, failure('field'))
      end

      def test_parameters_keep_a_flavor_tracked
        write('farm', 'tracked' => true, 'only' => ['units'])

        assert @loader.load('farm').unwrap!.with_parameters({}, name: 'mine').tracked?
      end

      def test_names_are_the_files_of_the_directory
        write('light', {})
        write('farm', 'tracked' => true, 'only' => ['units'])

        assert_equal %w[farm light], @loader.names
      end

      def test_the_flavors_of_the_repository_load
        loader = FlavorLoader.new(dir: SCHEMA.dirname.join('flavors'), validator: Common::Schema::ValidatorFactory.new(SCHEMA).build)

        assert_includes loader.names, 'cultia'
        loader.names.each { |name| loader.load(name).unwrap! }
        assert loader.load('cultia').unwrap!.tracked?
      end

      private

        def write(name, data)
          @dir.join("#{name}.yml").write({ 'name' => name }.merge(data).to_yaml)
        end

        def failure(name)
          assert_raises(StandardError) { @loader.load(name).unwrap! }.message
        end
    end
  end
end
