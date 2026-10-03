# frozen_string_literal: true

module Lexicon
  module Packaging
    # Splits the SQL of a table definition into the statements creating the tables and the ones
    # creating secondary indexes, so that indexes can be built after the data is loaded.
    class StructureSplitter
      INDEX_STATEMENT = /\ACREATE\s+(UNIQUE\s+)?INDEX\b/i.freeze
      DOLLAR_TAG = /\A\$[A-Za-z_]*\$/.freeze

      Result = Struct.new(:structure, :indexes)

      # @param [String] sql
      # @return [Result] arrays of statements, without their trailing semicolon
      def split(sql)
        indexes, structure = statements(sql).partition { |statement| index?(statement) }

        Result.new(structure, indexes)
      end

      # @param [String] sql
      # @return [Array<String>]
      def statements(sql)
        result = []
        current = +''
        position = 0

        while position < sql.length
          token = next_token(sql, position)
          if token == ';'
            result << current
            current = +''
          else
            current << token
          end
          position += token.length
        end

        [*result, current].map(&:strip).reject { |statement| blank?(statement) }
      end

      private

        # @return [String] the next character, or a whole quoted string or comment
        def next_token(sql, position)
          rest = sql[position..]

          if rest.start_with?('--')
            rest[/\A--[^\n]*/]
          elsif rest.start_with?('/*')
            delimited(rest, '/*', '*/')
          elsif rest.start_with?("'")
            quoted(rest, "'")
          elsif rest.start_with?('"')
            quoted(rest, '"')
          elsif (tag = rest[DOLLAR_TAG])
            delimited(rest, tag, tag)
          else
            rest[0]
          end
        end

        def delimited(rest, opening, closing)
          stop = rest.index(closing, opening.length)

          stop.nil? ? rest : rest[0, stop + closing.length]
        end

        # A doubled quote is an escaped quote: it does not close the string
        def quoted(rest, quote)
          position = 1
          loop do
            stop = rest.index(quote, position)
            return rest if stop.nil?
            return rest[0, stop + 1] if rest[stop + 1] != quote

            position = stop + 2
          end
        end

        def index?(statement)
          without_comments(statement).match?(INDEX_STATEMENT)
        end

        def blank?(statement)
          without_comments(statement).empty?
        end

        def without_comments(statement)
          statement.gsub(/--[^\n]*/, '').gsub(%r{/\*.*?\*/}m, '').strip
        end
    end
  end
end
