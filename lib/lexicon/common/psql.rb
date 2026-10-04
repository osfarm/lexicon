# frozen_string_literal: true

module Lexicon
  module Common
    class Psql
      # @param [String] url
      # @param [ShellExecutor] executor
      def initialize(url:, executor:)
        @url = url
        @executor = executor
      end

      # @param [String] command
      # @param [String, Array<String>] search_path
      def execute(command, search_path:)
        command = <<~SQL
          SET search_path TO #{Array(search_path).join(', ')};
          #{command}
        SQL

        execute_raw(command)
      end

      # @param [String] command
      def execute_raw(command)
        @executor.execute <<~BASH
          psql '#{url}' --quiet -c #{Shellwords.escape(command)}
        BASH
      end

      # @param [Pathname] file
      # @param [String, Array<String>] search_path
      def load_sql(file, search_path:)
        @executor.execute <<~BASH
          echo 'SET SEARCH_PATH TO #{Array(search_path).join(', ')};' | cat - #{file} | psql '#{url}'
        BASH
      end

      private

        # @return [ShellExecutor]
        attr_reader :executor
        # @return [String]
        attr_reader :url
    end
  end
end
