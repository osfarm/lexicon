# frozen_string_literal: true

module Datasources
  class Bsv
    # The rules of a `robots.txt` for every robot (`User-agent: *`): the longest matching rule wins, `Allow` over
    # `Disallow` when they are as long; `*` matches anything, a final `$` the end of the address.
    class Robots
      attr_reader :crawl_delay

      # @param [String] text
      # @return [Robots]
      def self.parse(text)
        rules = []
        delay = nil
        agents = []
        in_rules = false
        text.each_line do |line|
          field, value = line.sub(/#.*/, '').strip.split(/\s*:\s*/, 2)
          next if field.nil? || value.nil?

          case field.downcase
          when 'user-agent'
            agents = [] if in_rules
            in_rules = false
            agents << value
          when 'allow', 'disallow'
            in_rules = true
            rules << [field.downcase == 'allow', value] if agents.include?('*') && !value.empty?
          when 'crawl-delay'
            delay = value.to_f if agents.include?('*')
          end
        end
        new(rules, delay)
      end

      def initialize(rules, crawl_delay)
        @rules = rules.map { |allow, path| [allow, path, pattern(path)] }
        @crawl_delay = crawl_delay
      end

      # @param [String] path with its query
      # @return [Boolean]
      def allowed?(path)
        matching = @rules.select { |_, _, regexp| regexp.match?(path) }
        return true if matching.empty?

        best = matching.max_by { |allow, rule, _| [rule.length, allow ? 1 : 0] }
        best.first
      end

      private

        def pattern(path)
          anchored = path.end_with?('$')
          body = Regexp.escape(anchored ? path[0..-2] : path).gsub('\*', '.*')
          Regexp.new("\\A#{body}#{anchored ? '\z' : ''}")
        end
    end
  end
end
