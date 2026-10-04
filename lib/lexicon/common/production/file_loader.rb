# frozen_string_literal: true

module Lexicon
  module Common
    module Production
      class FileLoader
        # @param [ShellExecutor] shell
        # @param [String] database_url
        def initialize(shell:, database_url:)
          @shell = shell
          @database_url = database_url
        end

        # @param [Pathname] data_file
        # @return [Boolean]
        def load_file(data_file)
          if data_file.basename.to_s =~ /\.sql\z/
            load_sql(data_file)
          elsif data_file.basename.to_s =~ /\.sql\.gz\z/
            load_archive(data_file)
          else
            raise StandardError.new("Unknown file type: #{data_file.basename}")
          end
        end

        # @param [Pathname] archive
        # @return [Boolean]
        def load_archive(archive)
          shell.execute <<~BASH
            cat '#{archive}' | gzip -d | psql '#{database_url}'
          BASH

          true
        end

        # @param [Pathname] file
        # @return [Boolean]
        def load_sql(file)
          shell.execute <<~BASH
            echo psql '#{database_url}' < '#{file}'
          BASH

          true
        end

        private

          # @return [String]
          attr_reader :database_url
          # @return [ShellExecutor]
          attr_reader :shell
      end
    end
  end
end
