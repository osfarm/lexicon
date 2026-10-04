module Lexicon
  module Common
    module Mixin
      module Finalizable
        def self.included(base)
          class << base
            alias_method :_new, :new

            def new(*args, **options)
              e = do_call(self, '_new', args, options)

              ObjectSpace.define_finalizer(e, e.method(:_finalize))

              e
            end

            # Empty Array and Hash splats are handled correctly starting ruby 2.7:
            # if both args and kwargs are empty, no parameters are sent.
            if ::Semantic::Version.new(RUBY_VERSION).satisfies?('>= 2.7.0')
              private def do_call(obj, method, args, kwargs)
                obj.send(method, *args, **kwargs)
              end
            else
              private def do_call(obj, method, args, kwargs)
                if args.empty? && kwargs.empty?
                  obj.send(method)
                elsif args.empty?
                  obj.send(method, **kwargs)
                elsif kwargs.empty?
                  obj.send(method, *args)
                else
                  obj.send(method, *args, **kwargs)
                end
              end
            end
          end
        end

        private

          def finalize
            raise StandardError.new("Finalizer is not implemented in #{self.class.name}")
          end

          def _finalize(_id)
            m = method(:finalize)

            if !m.nil?
              finalize
            end
          rescue StandardError => e
            puts "Exception in finalizer: #{e.message}\n" + e.backtrace.join("\n")
          end
      end
    end
  end
end
