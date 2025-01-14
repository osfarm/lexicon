# frozen_string_literal: true

module Lexicon
  module Commands
    class DumpCommand < ContainerAwareCommand
      class_option :version, type: :string, default: nil
      class_option :validate, type: :boolean, default: true
      class_option :force, type: :boolean, default: false
      class_option :flavor, type: :string, default: nil

      desc 'all NAMES', 'Dumps all the lexicon'

      def all(*names)
        flavor = load_flavor(options.fetch('flavor', nil))

        make_package(names: names, flavor: flavor)
      end

      desc 'mobile', 'Dump the mobile version of the lexicon'

      def mobile
        version = options.fetch('version') { get('version') }
        dumper = get('database.mobile')

        dumper.dump(version: version)
      end

      private

        # @param [String, nil] name
        # @return [Flavor::LexiconFlavor, nil]
        def load_flavor(name)
          if name.nil?
            nil
          else
            # @type [Flavor::FlavorLoader] flavor_loader
            flavor_loader = container.resolve('flavor.loader')

            flavor_loader.load(name).unwrap!
          end
        end

        # @param [Array<String>] names
        # @param [Flavor::LexiconFlavor, nil] flavor
        def make_package(names:, flavor:)
          force = options.fetch('force', false)
          version = options.fetch('version') { get('version') }
          validate = options.fetch('validate', true)

          if !flavor.nil?
            puts "Dumping with flavor #{flavor.name}"
            version = "#{version}-#{flavor.name}"
          end

          # @type [Database::DataDumper] dumper
          dumper = get('database.dumper')
          # @type [Database::Validation::Validator]
          validator = get('database.validator')

          _valid, invalid = validator.validate_datasources.partition(&:valid?)

          if !validate || invalid.empty?
            # @type [Array<String>] names
            names = Array(names)
            package = dumper.make_package(
              Semantic::Version.new(version),
              only: (names.empty? ? nil : names),
              force: force,
              flavor: flavor
            )

            if package.nil?
              puts '[ NOK ] Package creation error'.red
            else
              puts '[  OK ] Package created successfully'.green
            end
          else
            puts "Unable to dump lexicon, some datasources are invalid: #{invalid.map(&:name).join(', ')}".red
          end
        end
    end
  end
end
