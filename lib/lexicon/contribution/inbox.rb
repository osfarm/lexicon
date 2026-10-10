# frozen_string_literal: true

require 'tmpdir'

module Lexicon
  module Contribution
    # What contributors proposed online, seen from the machine of a maintainer. The serving side keeps one
    # directory per workspace (the prefix of an API key), each holding one directory per dataset; a dataset
    # its author proposed carries a mark. Nothing here builds or publishes: a dataset is brought into
    # data/contributions, where it is reviewed and built like any other.
    class Inbox
      MARK = Web::App::PROPOSED
      NAME = /\A[a-z0-9][a-z0-9_]*\z/.freeze

      # @param [String] target directory of the contributions on the serving side, as rsync names it
      # @param [Packaging::Rsync] transfer
      def initialize(target:, transfer: Packaging::Rsync.new)
        @target = target.chomp('/')
        @transfer = transfer
      end

      # @return [Array<Hash>] :workspace, :name, :proposed_on, :description and :author of each proposed dataset
      def proposed
        Dir.mktmpdir('lexicon-inbox') do |tmp|
          # Only the marks and the sheets are read: tables stay where they are
          @transfer.fetch_directory(@target, tmp, filters: ['--prune-empty-dirs', '--include=/*/', '--include=/*/*/',
                                                            "--include=/*/*/#{MARK}", "--include=/*/*/#{Sheet::FILE}", '--exclude=*'])

          Pathname.new(tmp).glob("*/*/#{MARK}").sort.map { |mark| entry(mark) }
        end
      end

      # @param [String] workspace
      # @param [String] name
      # @param [Pathname] into directory of the contributions of this machine
      # @param [Boolean] force replace a dataset of that name
      # @return [Pathname] directory of the dataset
      def fetch(workspace, name, into:, force: false)
        raise ArgumentError.new('Designate a dataset as <workspace>/<name>') unless workspace.to_s.match?(NAME) && name.to_s.match?(NAME)

        destination = into.join(name)
        raise ArgumentError.new("#{destination} exists: --force replaces it") if destination.exist? && !force

        destination.mkpath
        @transfer.fetch_directory("#{@target}/#{workspace}/#{name}", destination, filters: ["--exclude=/#{MARK}"])
        destination
      end

      private

        def entry(mark)
          sheet = begin
            Sheet.load(mark.dirname)
          rescue Psych::Exception, SystemCallError
            nil
          end

          { workspace: mark.dirname.dirname.basename.to_s, name: mark.dirname.basename.to_s, proposed_on: mark.read.strip[0, 10],
            description: sheet&.description, author: sheet&.author }
        end
    end
  end
end
