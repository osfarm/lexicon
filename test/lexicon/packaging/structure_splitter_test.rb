# frozen_string_literal: true

require 'test_helper'

module Lexicon
  module Packaging
    class StructureSplitterTest < Minitest::Test
      def setup
        @splitter = StructureSplitter.new
      end

      def test_separates_indexes_from_tables
        result = @splitter.split(<<~SQL)
          CREATE TABLE things (
            id character varying PRIMARY KEY NOT NULL,
            name character varying
          );

          CREATE INDEX things_name ON things(name);
          CREATE UNIQUE INDEX things_id ON things(id);
          COMMENT ON COLUMN things.name IS 'The name';
        SQL

        assert_equal 2, result.structure.size
        assert_match(/\ACREATE TABLE things/, result.structure.first)
        assert_equal "COMMENT ON COLUMN things.name IS 'The name'", result.structure.last
        assert_equal ['CREATE INDEX things_name ON things(name)', 'CREATE UNIQUE INDEX things_id ON things(id)'], result.indexes
      end

      def test_keeps_semicolons_inside_strings_and_dollar_quotes
        statements = @splitter.statements(<<~SQL)
          COMMENT ON TABLE things IS 'first; second, it''s one';
          CREATE FUNCTION f() RETURNS integer AS $$ BEGIN RETURN 1; END; $$ LANGUAGE plpgsql;
          CREATE TABLE "odd;name" (id integer)
        SQL

        assert_equal 3, statements.size
        assert_equal "COMMENT ON TABLE things IS 'first; second, it''s one'", statements[0]
        assert_includes statements[1], 'RETURN 1; END;'
        assert_equal 'CREATE TABLE "odd;name" (id integer)', statements[2]
      end

      def test_ignores_semicolons_in_comments_and_drops_empty_statements
        statements = @splitter.statements(<<~SQL)
          -- a comment; with a semicolon
          CREATE TABLE things (id integer); /* another; one */
          ;
          -- trailing comment
        SQL

        assert_equal 1, statements.size
        assert_includes statements.first, 'CREATE TABLE things (id integer)'
      end

      def test_recognizes_a_commented_index_statement
        result = @splitter.split("-- lookup by name\nCREATE INDEX ON things(name);")

        assert_empty result.structure
        assert_equal 1, result.indexes.size
      end
    end
  end
end
