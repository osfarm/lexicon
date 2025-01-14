import os
import re
import sys
from datetime import datetime
from glob import glob
from os.path import dirname, join

import lxml.etree as treee
import unidecode as unidecode
import yaml
from psycopg2.extras import Json
from tqdm import tqdm
from lib.python import db_connect

# Define paths
DB_NAME = 'lexicon'
BASE_DIR = 'raw/phytosanitary'  # os.path.dirname(os.path.abspath(__file__))

def parse_usage_phrase(phrase):
    """Extract crop, application and function of a usage phrase"""

    #Puts transcoding words in function for pfi
    transcoding_words=["Désherbage","Dévitalisation","Trt Sol*Avt Plantation"]

    if any(word in phrase for word in transcoding_words):
        words = phrase.split('*', 1)
    else:
        words = phrase.split('*')

    crop = words[0]

    if len(words) > 2:
        application = words[1]
        function = words[2]
    else:
        application = None
        function = words[1]

    return crop, application, function  # Json({"fra": function}


def clean_crop(crop):
    """Normalize crop label"""

    if 'PPAM' not in crop and 'Porte graine' not in crop:
        crop=crop.capitalize()
    cleaned_crop=crop.replace('graminees','graminées')
    cleaned_crop=cleaned_crop.replace('écossées','écossés')
    cleaned_crop=cleaned_crop.replace(' - abricotier','')
    cleaned_crop=cleaned_crop.replace('Chataignier','Châtaignier')
    cleaned_crop=cleaned_crop.replace('Mais','Maïs')
    cleaned_crop=cleaned_crop.rstrip()

    return(cleaned_crop)


def clean_target(string):
    """Methode used to normalize phrases"""

    if string[0] == " ":
        string = string[1:]
    if string in ["RHIZOCTONIA","Rhizoctoniose"]:
        string = "Rhizoctone"
    if string == "SCLEROTINIA":
        string = "Sclérotiniose"
    if string == string.upper():
        string = string.capitalize()
        string = string.replace("couronnee", "couronnée")
    else:
        string = string[0].upper() + string[1:]

    string = string.replace(")", "")
    string = string.replace(" ( ", " ")
    string = string.replace("(", "")
    string = string.replace(" 1", "")
    string = string.replace("-", " ")

    for word in ["floraison", "ramification", "hybridation", "naturelles"]:
        string = string.replace(word, word.capitalize())
    for word in ["Ensilage", "Grains"]:
        string = string.replace(word, word.lower())

    string = string.replace("ion sur la", ".")
    if string[-1] in [" ", "."]:
        string = string[:-1]
    string = re.sub('\.(?=[^ ])', '. ', string)

    return string


def safe_date(string):
    """Methode used to normalize dates strings"""
    if string is None:
        return None

    dt = datetime.strptime(string, '%d/%m/%Y')

    # Fix for wrong year in xml file
    if dt.year == 16:
        dt = dt.replace(year=2016)

    date = dt.strftime("%Y-%m-%d") if dt else None
    return date if (date and len(date) == 10) else None


products_state_conversion={'AUTORISE':'authorized','RETIRE':'withdrawn'}
usages_state_conversion={'Autorisé':'authorized','Retrait':'withdrawn','Provisoire':'provisional'}

#mix_categroy_code for each H
H_risk_mix={'H341':2,'H351':2,'H371':2,'H361d':3,'H361f':3,'H361fd':3,'H362':3,'H373':4,'H300':5,'H301':5,'H310':5,'H311':5,'H330':5,
'H331':5,'H340':5,'H350':5,'H350i':5,'H360F':5,'H360D':5,'H360FD':5,'H360Fd':5,'H360Df':5,'H370':5,'H372':5}

#mix_categroy_code for each R
R_risk_mix={'R40':2,'R68':2,'R68/x':2,'R62':3,'R63':3,'R64':3,'R48/20':4,'R48/21':4,'R48/22':4,'R48/20/21':4,'R48/20/22':4,'R48/21/22':4,
'R48/20/21/22':4,'T':5,'T+':5}


def load_products_from_xml():
    """Load each kind of products from XML file"""

    # Get XML path and open it
    xmlfile = glob(os.path.join(BASE_DIR, 'xml/decision_intrant_opendata_*.xml'))[0]
    tree = treee.parse(xmlfile)

    # Connect to database
    conn = db_connect()
    curs = conn.cursor()

    # Load units
    with open(join(dirname(__file__), "units.yml"), 'r') as f:
        units_dict = yaml.load(f, Loader=yaml.FullLoader)


    # Process files
    try:
        for type_produit in [ 'PPP', 'adjuvant', 'produit-mixte']:

            # Loop for each PPP
            for node in tqdm(tree.xpath("//{}".format(type_produit)),
                             desc="Load and process {} from XML".format(type_produit), ascii=True):

                ##################################
                #          SAVE PRODUCT          #
                ##################################

                # Get MAAID number
                # Beware that 2090141 BARBARIAN SUPER 360 has an extra whitespace at the beginning of the AMM number tag content, hence the need of using strip function
                maaid = node.findtext('numero-AMM').strip()
                if maaid == 'N/A':
                    continue

                # Get main name
                name = node.findtext('nom-produit')

                reference_name = re.sub('[^a-zA-Z0-9]$', '', (maaid + '_' + re.sub('[^a-zA-Z0-9]', '_', name.lower())))

                # Get other names
                _other_names = list()
                for i in node.xpath('autres-noms/autre-nom'):
                    _other_name = i.find('nom')
                    _other_names.append(_other_name.text)
                other_names = _other_names if _other_names else None

                # Get natures
                _natures = list()
                for i in node.xpath('fonctions/ref'):
                    _natures.append(i.text)
                natures = _natures if _natures else None

                # Get active compounds
                active_compounds = list()
                for i in node.xpath('composition-integrale/substances-actives/substance-active'):
                    _substance = i.find('substance')
                    _teneur = i.find('teneur-SA-pure')
                    if _substance is not None:
                        _compound = _substance.text
                        if _teneur is not None:
                            _compound += " {} {}".format(_teneur.text, _teneur.get('unite'))
                        active_compounds.append(_compound)

                # Get and extract operator protection mentions
                _operator_protection = node.xpath("conditions-emploi-produit/condition-emploi-produit[condition-"
                                                  "emploi-categorie=\"Protection de l'opérateur\"]/description")
                operator_protection_mentions = _operator_protection[0].text if _operator_protection else None

                # Get state of the product
                _etat_produit = node.findtext('etat-produit')
                state = products_state_conversion[_etat_produit]

                # Get first auth date
                _date = node.findtext('date-premiere-autorisation')
                started_on = safe_date(_date)

                # Get stop date based on end of allowed usage (max, can be change to min)
                stopped_on = None
                if state == 'withdrawn':
                    _end_list = list()
                    for i in node.xpath('usages/usage/date-fin-utilisation'):
                        _end_list.append(datetime.strptime(i.text, '%d/%m/%Y').strftime("%Y-%m-%d"))
                    if _end_list:
                        stopped_on = max(_end_list)
                    # for i in node.xpath('usages/usage'):
                    #     if i.find('date-fin-utilisation').text == 'Retrait' and i.get('date-decision'):
                    #         stopped_on = datetime.strptime(i.get('date-decision'), '%d/%m/%Y').strftime("%Y-%m-%d")
                    #         break

                # Get allowed mentions
                _mentions = dict()
                for i in node.xpath('mentions-autorisees/ref'):
                    if i.text == 'Utilisable en agriculture biologique':
                        _mentions['organic_usage'] = True
                    elif i.text == 'Mention abeille':
                        _mentions['bee_usage'] = True
                    elif i.text == 'Liste biocontrôle':
                        _mentions['biocontrol_usage'] = True
                allowed_mentions = Json(_mentions) if _mentions else None

                # Get restricted mentions
                _restricted = [i.text for i in node.xpath('restrictions-usage/ref')]
                restricted_mentions = " | ".join(_restricted) if _restricted else None

                # Get firm name
                firm_name = node.findtext('titulaire')

                # Get product type
                product_type = node.findtext('type-produit')


                # print((maaid, name, other_name, nature, active_compounds, maaid, 0, in_field_reentry_delay,
                #               state, started_on, stopped_on, Json(allowed_mentions), restricted_mentions, firm_name,
                #               product_type))

                in_field_reentry_delay = 6
                mix_category_codes={1}

                #insert "H" risk
                for i in node.xpath('classement-CLP/phrases-risque/ref'):
                    curs.execute("INSERT INTO lexicon.registered_phytosanitary_risks "
                                 "VALUES (%s, %s, %s) "
                                 "ON CONFLICT DO NOTHING",
                                 (maaid, i.get('lib-court'), i.text))

                    #update in_field_reentry_delay if danger
                    if i.get('lib-court') in ["H317","H334"] and in_field_reentry_delay < 48:
                        in_field_reentry_delay = 48
                    elif i.get('lib-court') in ["H315","H318","H319"] and in_field_reentry_delay < 24:
                        in_field_reentry_delay = 24

                    #update mix_category_code if danger
                    if i.get('lib-court') in H_risk_mix.keys():
                        mix_category_codes.add(H_risk_mix[i.get('lib-court')])


                #insert "R" risk
                for i in node.xpath('classement-DSD/phrases-risque/ref'):
                    #ignore risk phrase if not "R"
                    if i.get('lib-court')[0] == "R":
                        curs.execute("INSERT INTO lexicon.registered_phytosanitary_risks "
                                    "VALUES (%s, %s, %s) "
                                    "ON CONFLICT DO NOTHING",
                                    (maaid, i.get('lib-court'), i.text))

                        #update in_field_reentry_delay if danger
                        if i.get('lib-court') in ["R42","R43"] and in_field_reentry_delay < 48:
                            in_field_reentry_delay = 48
                        elif i.get('lib-court') in ["R36","R38","R41"] and in_field_reentry_delay < 24:
                            in_field_reentry_delay = 24

                        #update mix_category_code if danger
                        if i.get('lib-court') in R_risk_mix.keys():
                            mix_category_codes.add(R_risk_mix[i.get('lib-court')])

                in_field_reentry_delay=str(in_field_reentry_delay)+' hours'
                mix_category_codes=sorted(mix_category_codes)

                curs.execute("INSERT INTO lexicon.registered_phytosanitary_products "
                             "VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s) "
                             "ON CONFLICT DO NOTHING",
                             (maaid, reference_name, name, other_names, natures, active_compounds, maaid, mix_category_codes, in_field_reentry_delay,
                              state, started_on, stopped_on, allowed_mentions, restricted_mentions,
                              operator_protection_mentions, firm_name, product_type))


                ##################################
                #          SAVE  USAGES          #
                ##################################

                for i in node.xpath('usages/usage'):

                    # Init to null values to keep database clean 
                    species = '{plant}'
                    description = None
                    dose_quantity = None
                    dose_unit = None
                    dose_unit_name = None
                    dose_unit_factor = None
                    pre_harvest_delay = '3 days'
                    pre_harvest_delay_bbch = None
                    applications_count = None
                    applications_frequency = None
                    development_stage_min = None
                    development_stage_max = None
                    usage_conditions = None
                    untreated_buffer_aquatic = None
                    untreated_buffer_arthropod = None
                    untreated_buffer_plants = None
                    lib_court = None

                    # Get usage decision date
                    decision_date = safe_date(i.get('date-decision'))

                    # Get state of the usage
                    _etat_usage = i.find('etat-usage').text
                    state = usages_state_conversion[_etat_usage]

                    # Get usage phrase
                    _usage_id = i.find('identifiant-usage')
                    if _usage_id is not None:
                        ephy_usage_phrase = _usage_id.text
                        lib_court = int(_usage_id.get('lib-court'))

                    # Get unique id of usage
                    ephy_usage_id = i.find('id').text

                    # Get dose and unit
                    _quantity = i.find('dose-retenue')
                    if _quantity is not None:
                        dose_quantity = _quantity.text
                        dose_unit_name = _quantity.get('unite')
                        dose_unit, dose_unit_factor = normalize_unit(units_dict, dose_unit_name)

                    # Get pre harvest delay
                    _harvest_delay = i.find('delai-avant-recolte-jour')
                    if _harvest_delay is not None:
                        pre_harvest_delay = _harvest_delay.text + ' days'

                    # Get pre harvest delay (BBCH)
                    _harvest_delay_bbch = i.find('delai-avant-recolte-bbch')
                    if _harvest_delay_bbch is not None:
                        pre_harvest_delay_bbch = int(_harvest_delay_bbch.text)

                    # Application count
                    _max_applications = i.find('nombre-apport-max')
                    if _max_applications is not None:
                        applications_count = int(_max_applications.text)

                    # Min interval
                    # _freq = i.find('condition-emploi')
                    # if _freq is not None:
                    #     match = re.search(r".*Intervalle minimum entre les applications\s?:\s?(\d+).*",
                    #                       _freq.text, re.IGNORECASE)
                    #     if match:
                    #         print(match.group(1))

                    _stage_min = i.find('stade-cultural-min')
                    if _stage_min is not None:
                        development_stage_min = int(_stage_min.text)

                    _stage_max = i.find('stade-cultural-max')
                    if _stage_max is not None:
                        development_stage_max = int(_stage_max.text)

                    _usage_conditions = i.find('condition-emploi')
                    if _usage_conditions is not None:
                        usage_conditions = _usage_conditions.text

                    _znt_aqua = i.find('ZNT-aquatique')
                    if _znt_aqua is not None:
                        untreated_buffer_aquatic = int(float(_znt_aqua.text))

                    _znt_arthro = i.find('ZNT-arthropodes-non-cibles')
                    if _znt_arthro is not None:
                        untreated_buffer_arthropod = int(float(_znt_arthro.text))

                    _znt_plant = i.find('ZNT-plantes-non-cibles')
                    if _znt_plant is not None:
                        untreated_buffer_plants = int(float(_znt_plant.text))

                    # TODO :: Normalize target_name & treatment (they can be inverted today, not realy fiable)
                    _crop_name, _treatment, _function = parse_usage_phrase(ephy_usage_phrase)
                    crop_name=clean_crop(_crop_name)
                    crop_name_json = Json({"fra": crop_name})
                    target_name_fra = clean_target(_function)
                    target_name = Json({"fra": target_name_fra})
                    treatment = Json({"fra": _treatment}) if _treatment else None

                    data = (ephy_usage_id, lib_court, maaid, ephy_usage_phrase, crop_name_json, crop_name, species, target_name, target_name_fra,
                            description, treatment, dose_quantity, dose_unit, dose_unit_name, dose_unit_factor,
                            pre_harvest_delay, pre_harvest_delay_bbch,applications_count, applications_frequency,
                            development_stage_min, development_stage_max, usage_conditions, untreated_buffer_aquatic,
                            untreated_buffer_arthropod, untreated_buffer_plants, decision_date, state)

                    if crop_name != "Usages non agricoles":
                        curs.execute("INSERT INTO lexicon.registered_phytosanitary_usages VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, "
                        "%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s) ", data)

    finally:
        conn.commit()
        curs.close()
        conn.close()


def normalize_unit(dic, string):

    for unit in dic.items():
        for label, factor in unit[1].items():
            if label == string:
                return unit[0], factor
    return None, None


def find_product(amm):
    xmlfile = glob(os.path.join(BASE_DIR, 'archive/decision_intrant_opendata_*.xml'))[0]
    tree = treee.parse(xmlfile)
    print(sys.getsizeof(xmlfile))
    for node in tree.xpath('//PPP'):
        if node.findtext('numero-AMM') == str(amm):
            print("{} ##################################################".format(node.findtext('nom-produit')))
            break
