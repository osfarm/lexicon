# frozen_string_literal: true

module Lexicon
  module Server
    # Removes what is no longer wanted: old versions in the repository, and packages in service that
    # the repository no longer has.
    class Pruner
      Plan = Struct.new(:versions, :packages, keyword_init: true) do
        def empty?
          versions.empty? && packages.empty?
        end
      end

      # @param [Packaging::Repository] repository
      # @param [Packaging::Retention] retention
      # @param [Meta] meta
      # @param [Swapper] swapper
      def initialize(repository:, retention:, meta:, swapper:)
        @repository = repository
        @retention = retention
        @meta = meta
        @swapper = swapper
      end

      # @return [Plan] versions as [name, version] pairs, packages as names
      def plan
        meta.setup
        in_service = meta.all_installed.map { |package| [package.name, package.version] }.to_h

        Plan.new(
          versions: repository.names.flat_map do |name|
            protect = [in_service[name], repository.current(name)]

            retention.expired(name, repository.versions(name), protect: protect).map { |version| [name, version] }
          end,
          packages: in_service.keys - repository.names
        )
      end

      # @param [Plan] plan
      def apply(plan)
        plan.versions.each { |name, version| repository.delete(name, version) }
        plan.packages.each do |name|
          swapper.remove(meta.tables_of(name)) { meta.remove_package(name) }
        end
      end

      private

        # @return [Packaging::Repository]
        attr_reader :repository
        # @return [Packaging::Retention]
        attr_reader :retention
        # @return [Meta]
        attr_reader :meta
        # @return [Swapper]
        attr_reader :swapper
    end
  end
end
