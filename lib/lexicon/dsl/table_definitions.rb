# frozen_string_literal: true

module Lexicon
  module Dsl
    module TableDefinitions
      extend ActiveSupport::Concern

      def table_builder
        self.class.table_builder
      end

      module ClassMethods
        def table_builder
          @table_builder ||= Lexicon::Database::Schema::TableBuilder.new
        end

        def table_definitions(&block)
          block.call(table_builder)
        end
      end
    end
  end
end
