import os
import psycopg2
from psycopg2 import sql
from tqdm import tqdm


# Define paths
src_dir = 'archive'
src_path = 'raw/phyto'
db_name = 'lexicon'
tmp_schema = 'phyto'
python_path = os.path.dirname(os.path.abspath(__file__))


def load(date):

    # Creates empty tables dict
    tables = {}

    # Open connexion to database
    with psycopg2.connect(dbname=db_name) as conn:
        with conn.cursor() as curs:

            # Override database from SQL file
            print("---\nDatabase override")
            curs.execute(open(os.path.join(python_path, "original_schema.sql"), "r").read())

            # Get all tables names and fill <tables> dictionary
            curs.execute("SELECT table_name FROM information_schema.tables WHERE table_schema = %s;", [tmp_schema])
            schema = curs.fetchall()
            for table in schema:
                tables[table[0]] = []

            # Do opperations for each table
            for table in tables.keys():

                # Get columns names for each table and save it to respective <tables> dictionary entry
                curs.execute("SELECT column_name FROM information_schema.columns WHERE table_name = %s;", [table])
                columns = curs.fetchall()
                for column in columns:
                    tables[table].append(column[0])
                tables[table] = tuple(tables[table])

                # Loads file into respective table
                file = "{table}_{date}.csv".format(table=table, date=date)
                print("---\nProcessing {file} ({nb} parameters)...".format(file=file, nb=len(columns)))
                with open(os.path.join(src_path, src_dir, file), 'r', encoding='windows-1252') as f:
                    length = len(f.readlines())
                    f.seek(0)
                    for row in tqdm(f, total=length, unit_scale=True, unit_divisor=1024):
                        values = row.rstrip('\n').replace('"', '').split(';')
                        clean_values = tuple(value if value != '' else None for value in values)
                        curs.execute(sql.SQL("""INSERT INTO "phyto".{table} VALUES %s;""")
                                     .format(table=sql.Identifier(table)), (clean_values,))

            # Applies constraints
            print("---\nApplies constraints")
            curs.execute(open(os.path.join(python_path, "constraints.sql"), "r").read())


def compute_mix_category_code():

    with psycopg2.connect(dbname=db_name) as conn:
        with conn.cursor() as curs:

            curs.execute("SELECT id FROM lexicon.registered_phytosanitary_products ORDER BY id;")
            products = curs.fetchall()

            for product_id in products:
                curs.execute(
                    "SELECT p.phrase_code as risk FROM lexicon.registered_phytosanitary_phrases as p "
                    "WHERE p.product_id = %s "
                    "UNION SELECT r.risk_code as risk FROM lexicon.registered_phytosanitary_risks as r "
                    "WHERE r.product_id = %s", [product_id[0], product_id[0]]
                )

                risks_codes = curs.fetchall()
                mix_category_code = 0

                for codes in risks_codes:
                    for code in codes[0].split(' + '):
                        print("code: {}".format(code))
                        if code in "H300, H301, H310, H311, H330, H331, H340, H350, H350i, " \
                                   "H360F, H360D, H360FD, H360Fd, H360Df, H370, H372, T, T+":
                            mix_category_code = 5

                        elif code in "H373, R48/20, R48/21, R48/22, R48/20/21, R48/20/22, R48/21/22, R48/20/21/22":
                            mix_category_code = 4 if mix_category_code < 4 else mix_category_code

                        elif code in "H361d, H361f, H361fd, H362, R62, R63, R64":
                            mix_category_code = 3 if mix_category_code < 3 else mix_category_code

                        elif code in "H341, H351, H371, R40, R68, R68/x":
                            mix_category_code = 2 if mix_category_code < 2 else mix_category_code

                if mix_category_code < 1:
                    mix_category_code = 1

                curs.execute("UPDATE lexicon.registered_phytosanitary_products "
                             "SET mix_category_code = %s WHERE id = %s;", (mix_category_code, product_id[0]))
