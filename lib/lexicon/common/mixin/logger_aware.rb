# frozen_string_literal: true

module Lexicon
  module Common
    module Mixin
      module LoggerAware
        # @return [Logger]
        attr_accessor :logger

        def log(*args, **options)
          if !logger.nil?
            logger.debug(*args, **options)
          end
        end

        def log_error(error)
          if error.nil?
            log('Error (nil)')
          elsif !logger.nil?
            logger.error([error.message, *error.backtrace].join("\n"))
          end
        end
      end
    end
  end
end
