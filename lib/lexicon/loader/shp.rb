# frozen_string_literal: true

module Lexicon
  module Loader
    class Shp

      # @param [ShellExecutor] executor
      # @param [String] db_url
      def initialize(executor:, db_url:)
        @db_url = db_url
        @executor = executor
      end

      # @param [Pathname] file
      # @param [String] srid
      # @param [Boolean] create
      # @param [Boolean] load
      # @param [String] charset
      # @param [String] table_name
      # @param [Array<String>] search_path
      def load(file, srid: '2154', create: true, load: true, charset: 'latin1', table_name:, search_path:)
        args = if create && load
                 '-D -c -I'
               elsif create
                 '-p -I'
               elsif load
                 '-D -a'
               else
                 nil
               end
        return if args.nil?

        @executor.execute <<-BASH
          echo 'SET search_path TO #{Array(search_path).join(', ')};' | cat - <(shp2pgsql -s '#{srid}' #{args} -W '#{charset}' #{file.expand_path} '#{table_name}') | psql '#{@db_url}' -v ON_ERROR_STOP=1 -q
        BASH
      end
    end
  end
end
