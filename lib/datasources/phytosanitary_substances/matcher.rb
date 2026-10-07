# frozen_string_literal: true

module Datasources
  class PhytosanitarySubstances
    # Finds, for an active substance named by E-Phy, its line in a list published by someone else (EIQ
    # values of Cornell, mode of action of the HRAC). Lists name the form that is sold (an ester, a salt)
    # where E-Phy often names the acid, and the other way round: each match says how it was made, so that
    # a reader can keep the exact ones only.
    #
    # A mode of action belongs to the acid, whatever its salt, ester or isomer: the HRAC list is matched
    # with `isomers` and `forms`. A toxicity does not: for the EIQ, another form only matches when a
    # line of the aliases file says so.
    class Matcher
      Match = Struct.new(:entry, :how, keyword_init: true)

      CAS = 'cas'       # same CAS number
      NAME = 'name'     # same name
      ISOMER = 'isomer' # same name once the isomer mark (-P, -M) is dropped
      FORM = 'form'     # one names the acid, the other one of its salts or esters
      ALIAS = 'alias'   # written by hand in data/phytosanitary_substances/aliases.csv

      # @param [String] value
      # @return [String] lower case words and numbers, whatever the punctuation
      def self.normalize(value)
        value.to_s.gsub(/<[^>]+>/, '').downcase.gsub(/[^a-z0-9]+/, ' ').strip
      end

      # @param [Array<Hash>] entries lines of the list, each with :name and optionally :cas and :group
      # @param [Hash{String => String}] aliases name of the list for a name of E-Phy
      # @param [Boolean] isomers whether an isomer shares what the list says of the substance
      # @param [Boolean] forms whether a salt or an ester shares what the list says of the acid
      def initialize(entries, aliases: {}, isomers: false, forms: false)
        @by_name = {}
        entries.each do |entry|
          # "Allidochlor=CDAA" gives two names to the same line
          entry[:name].to_s.split('=').each { |name| @by_name[self.class.normalize(name)] ||= entry }
        end
        @by_cas = entries.reject { |entry| entry[:cas].to_s.strip.empty? }.to_h { |entry| [entry[:cas].strip, entry] }
        @aliases = aliases.to_h { |ephy, list| [self.class.normalize(ephy), self.class.normalize(list)] }
        @isomers = isomers
        @forms = forms
      end

      # @param [String] name
      # @param [String, nil] cas
      # @return [Match, nil]
      def match(name, cas: nil)
        key = self.class.normalize(name)
        return nil if key.empty?

        # "Diquat (dibromide)", "Valifenalate (formerly Valiphenal)": what E-Phy adds between parentheses
        plain = self.class.normalize(name.to_s.gsub(/\s*\([^()]*\)/, ''))

        by_alias(key) || by_cas(cas) || by_name(key, NAME) || by_name(plain, NAME) || by_isomer(plain) || by_form(plain)
      end

      private

        def by_alias(key)
          entry = @by_name[@aliases[key]]

          entry && Match.new(entry: entry, how: ALIAS)
        end

        def by_cas(cas)
          entry = @by_cas[cas.to_s.strip]

          entry && Match.new(entry: entry, how: CAS)
        end

        def by_name(key, how)
          entry = @by_name[key]

          entry && Match.new(entry: entry, how: how)
        end

        def by_isomer(key)
          return nil unless @isomers

          plain = without_isomer(key)

          plain == key ? nil : by_name(plain, ISOMER) || by_form(plain)
        end

        # "mecoprop p" is the active isomer of "mecoprop"
        def without_isomer(key)
          key.split.reject { |word| %w[p m].include?(word) }.join(' ')
        end

        # A longer name starting with the shorter one, as long as every candidate says the same thing
        def by_form(key)
          return nil unless @forms

          candidates = @by_name.select { |name, _| name.start_with?("#{key} ") || key.start_with?("#{name} ") }.values.uniq
          return nil if candidates.empty? || candidates.map { |entry| entry[:group] }.uniq.size > 1

          Match.new(entry: candidates.first, how: FORM)
        end
    end
  end
end
