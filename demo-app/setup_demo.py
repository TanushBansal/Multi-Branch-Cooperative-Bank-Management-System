"""Create a NEW demo database; refuses to replace an existing database."""
import re
from pathlib import Path
import server


def create_demo(name='CooperativeBankDemo'):
    if not re.fullmatch(r'[A-Za-z][A-Za-z0-9_]{0,63}', name):
        raise ValueError('Invalid demo database name')
    source = Path(__file__).resolve().parent.parent / 'database'
    # Fail before making any change if the application procedure cannot be located.
    loans = (source / '05_loans.sql').read_text(encoding='utf-8-sig')
    match = re.search(r'CREATE PROCEDURE ApplyLoan\s*\(.*?END\s*\$\$', loans, re.S | re.I)
    if not match:
        raise ValueError('Cannot locate ApplyLoan in 05_loans.sql')
    server.query('CREATE DATABASE `' + name + '`;')
    try:
        for filename in ['01_schema.sql', '02_constraints_triggers.sql', '02_account_opening.sql',
                         '02_loan_dates.sql', '03_seed_data.sql', '04_transactions.sql', '06_views.sql']:
            sql = (source / filename).read_text(encoding='utf-8-sig')
            sql = re.sub(r'CREATE DATABASE IF NOT EXISTS CooperativeBank\s*;', '', sql, flags=re.I)
            sql = re.sub(r'USE CooperativeBank\s*;', 'USE `' + name + '`;', sql, flags=re.I)
            server.query(sql)
        server.query('USE `' + name + '`;\nDELIMITER $$\n' + match.group(0) + '\nDELIMITER ;\n')
    except Exception:
        print('Setup stopped. The newly created database was retained for inspection; no reset was attempted.')
        raise
    print('Created ' + name + ' with sample data and seven supported operation procedures.')


if __name__ == '__main__':
    import argparse
    import getpass
    import os
    import shutil
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--name', default='CooperativeBankDemo')
    parser.add_argument('--password', action='store_true')
    args = parser.parse_args()
    client = shutil.which('mysql') or r'C:\Program Files\MySQL\MySQL Server 8.0\bin\mysql.exe'
    server.MYSQL_ARGS = [client, '--login-path=local']
    if args.password:
        os.environ['MYSQL_PWD'] = getpass.getpass('MySQL root password (not saved): ')
        server.MYSQL_ARGS = [client, '--host=127.0.0.1', '--user=root']
    server.MYSQL_ARGS += ['--xml', '--batch', '--default-character-set=utf8mb4']
    create_demo(args.name)
