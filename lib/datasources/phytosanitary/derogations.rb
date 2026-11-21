# frozen_string_literal: true

module Datasources
  class Phytosanitary
    # Authorisations of plant protection products for at most 120 days (article 53 of regulation (EC) 1107/2009).
    # E-Phy does not publish them: the ministry of agriculture lists them on a page, one decision per PDF.
    #
    # `collect` keeps every PDF ever seen in `raw/phytosanitary/derogations/` and has each read once: the text of its
    # pages by `ocr.py` (PyMuPDF, Tesseract for a scan), the fields by Claude Haiku (`Archive`, `Page`, `Reader`);
    # `load` checks the readings and writes the rows (`Decision`, `Rows`) without the network; `normalize` adds them
    # to the tables of E-Phy. See `claudedocs/design_phyto_derogations.md`.
    module Derogations
      PAGE_URL = 'https://agriculture.gouv.fr/produits-phytopharmaceutiques-autorisations-de-mise-sur-le-marche-dune-duree-maximale-de-120-jours'
      USER_AGENT = 'Lexicon OSFarm (+https://lexicon.osfarm.org)'
      MODEL = 'claude-haiku-5-5'
      # 120 days, and a margin for a decision whose dates are rounded at publication
      MAX_DAYS = 130

      string = { 'type' => 'string' }.freeze
      nullable = ->(type) { { 'anyOf' => [{ 'type' => type }, { 'type' => 'null' }] } }
      object = lambda do |properties|
        { 'type' => 'object', 'additionalProperties' => false, 'required' => properties.keys, 'properties' => properties }
      end

      # Strict schema: every property is required. A text not found is an empty string (`Decision` reads it as nil),
      # only the numbers are nullable: the API refuses a schema with more than a few unions of types
      SCHEMA = object.call(
        'amm' => { 'type' => 'string' },
        'name' => { 'type' => 'string' },
        'titulaire' => string,
        'substances' => { 'type' => 'array', 'items' => object.call(
          'substance' => string,
          'value' => string,
          'unit' => string
        ) },
        'danger_statements' => { 'type' => 'array', 'items' => object.call(
          'code' => string,
          'phrase' => string
        ) },
        'conditions' => { 'type' => 'array', 'items' => { 'type' => 'string' } },
        'derogation_start' => string,
        'derogation_end' => string,
        'usages' => { 'type' => 'array', 'items' => object.call(
          'code_usage' => string,
          'libelle' => string,
          'crop_restriction' => string,
          'milieu' => string,
          'dose_max' => nullable.call('number'),
          'unite_dose_max' => string,
          'max_application_phrase' => string,
          'bbch_min' => nullable.call('integer'),
          'bbch_max' => nullable.call('integer'),
          'dar_jour' => nullable.call('integer')
        ) }
      ).freeze

      SYSTEM = <<~TEXT.squish.freeze
        Tu reçois le texte, page par page, d'une décision française d'autorisation de mise sur le marché d'un produit
        phytopharmaceutique au titre de l'article 53 (dérogation de 120 jours au plus). Remplis les champs à partir de
        ce texte seul : recopie ce qui est écrit, ne devine rien ; un
        texte absent est une chaîne vide, un nombre absent est null. amm : le
        numéro d'AMM à 7 chiffres. derogation_start et derogation_end : les
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
