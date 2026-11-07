# frozen_string_literal: true

module Datasources
  class Phytosanitary
    # Authorisations of plant protection products for at most 120 days (article 53 of regulation (EC) 1107/2009).
    # E-Phy does not publish them: the ministry of agriculture lists them on a page, one decision per PDF.
    #
    # `collect` keeps every PDF ever seen in `raw/phytosanitary/derogations/` and has each read once by Mistral OCR
    # (`Archive`, `Page`, `Reader`); `load` checks the readings and writes the rows (`Decision`, `Rows`) without the
    # network; `normalize` adds them to the tables of E-Phy. See `claudedocs/design_phyto_derogations.md`.
    module Derogations
      PAGE_URL = 'https://agriculture.gouv.fr/produits-phytopharmaceutiques-autorisations-de-mise-sur-le-marche-dune-duree-maximale-de-120-jours'
      USER_AGENT = 'Lexicon OSFarm (+https://lexicon.osfarm.org)'
      OCR_MODEL = 'mistral-ocr-latest'
      # `document_annotation` of Mistral OCR reads 8 pages at most; a decision has about 4
      MAX_PAGES = 8
      # 120 days, and a margin for a decision whose dates are rounded at publication
      MAX_DAYS = 130

      nullable = ->(type) { { 'type' => [type, 'null'] } }
      object = lambda do |properties|
        { 'type' => 'object', 'additionalProperties' => false, 'required' => properties.keys, 'properties' => properties }
      end

      # Strict schema: every property is required, the optional ones are nullable
      SCHEMA = object.call(
        'amm' => { 'type' => 'string' },
        'name' => { 'type' => 'string' },
        'titulaire' => nullable.call('string'),
        'substances' => { 'type' => 'array', 'items' => object.call(
          'substance' => nullable.call('string'),
          'value' => nullable.call('string'),
          'unit' => nullable.call('string')
        ) },
        'danger_statements' => { 'type' => 'array', 'items' => object.call(
          'code' => nullable.call('string'),
          'phrase' => nullable.call('string')
        ) },
        'conditions' => { 'type' => 'array', 'items' => { 'type' => 'string' } },
        'derogation_start' => nullable.call('string'),
        'derogation_end' => nullable.call('string'),
        'usages' => { 'type' => 'array', 'items' => object.call(
          'code_usage' => nullable.call('string'),
          'libelle' => nullable.call('string'),
          'crop_restriction' => nullable.call('string'),
          'milieu' => nullable.call('string'),
          'dose_max' => nullable.call('number'),
          'unite_dose_max' => nullable.call('string'),
          'max_application_phrase' => nullable.call('string'),
          'bbch_min' => nullable.call('integer'),
          'bbch_max' => nullable.call('integer'),
          'dar_jour' => nullable.call('integer')
        ) }
      ).freeze

      INSTRUCTIONS = <<~TEXT.squish.freeze
        Décision française d'autorisation de mise sur le marché d'un produit phytopharmaceutique au titre de l'article 53
        (dérogation de 120 jours au plus). amm : le numéro d'AMM à 7 chiffres. derogation_start et derogation_end : les
        dates « délivrée en France du … au … », au format AAAA-MM-JJ. danger_statements : les mentions de danger (code H
        et phrase). conditions : chaque condition d'emploi telle qu'écrite (SP 1, SPe 3, protection de l'opérateur, délai
        de rentrée…). usages : une ligne par ligne du tableau « Usage(s) autorisé(s) » ; code_usage : le code de
        l'usage ; libelle : le libellé tel qu'écrit, avec ses astérisques ; crop_restriction : la colonne « Autorisé(s)
        uniquement sur la(es) culture(s) suivante(s) » sans le milieu ; milieu : « Plein champ » ou « Sous abris » quand
        la ligne le précise ; dose_max : le nombre de la dose maximale par application ; unite_dose_max : son unité
        telle qu'écrite (L/ha, kg/ha…) ; max_application_phrase : la colonne du nombre d'applications telle qu'écrite ;
        bbch_min et bbch_max : les stades BBCH ; dar_jour : le délai avant récolte en jours, null s'il est « / ».
      TEXT
    end
  end
end
