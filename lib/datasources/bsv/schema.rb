# frozen_string_literal: true

require 'digest'
require 'json'

module Datasources
  class Bsv
    # What the Claude API must answer for a bulletin (structured output), and the instructions it reads
    # (`data/bsv/consigne.md`). The version of an extraction is the fingerprint of both: changing either does not
    # extract anything again by itself, the version kept beside each answer says which one it followed.
    module Schema
      INSTRUCTIONS = Pathname.new('data/bsv/consigne.md')

      LEVELS = %w[nul faible moyen fort tres_fort non_precise].freeze
      TYPES = %w[maladie ravageur adventice auxiliaire physiologique].freeze
      NATURES = %w[bulletin bilan note].freeze

      STRING = { type: 'string' }.freeze
      INTEGER = { type: 'integer' }.freeze

      def self.nullable(schema)
        { anyOf: [schema, { type: 'null' }] }
      end

      def self.object(properties)
        { type: 'object', properties: properties, required: properties.keys.map(&:to_s), additionalProperties: false }
      end

      LINE = object(
        culture: STRING,
        bioagresseur: nullable(STRING),
        type: nullable({ type: 'string', enum: TYPES }),
        stade: nullable(STRING),
        bbch_min: nullable(INTEGER),
        bbch_max: nullable(INTEGER),
        zadoks_min: nullable(INTEGER),
        zadoks_max: nullable(INTEGER),
        niveau: { type: 'string', enum: LEVELS },
        conditionnel: { type: 'boolean' },
        condition: nullable(STRING),
        niveau_texte: nullable(STRING),
        periode_risque: nullable(STRING),
        seuil: nullable(STRING),
        observations: nullable(STRING),
        lieux: { type: 'array', items: STRING },
        page: INTEGER,
        extrait: STRING
      ).freeze

      SCHEMA = object(
        region: STRING,
        regions_citees: { type: 'array', items: STRING },
        zone: nullable(STRING),
        filiere: STRING,
        sous_filiere: nullable(STRING),
        numero: nullable(STRING),
        date: { type: 'string', format: 'date' },
        nature: { type: 'string', enum: NATURES },
        lignes: { type: 'array', items: LINE },
        remarques: STRING
      ).freeze

      # @return [String] the instructions given as system prompt
      def self.instructions
        INSTRUCTIONS.read
      end

      # @return [String] 12 characters that change with the instructions or the schema
      def self.version
        Digest::SHA256.hexdigest(instructions + JSON.generate(SCHEMA))[0, 12]
      end
    end
  end
end
