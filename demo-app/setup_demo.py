"""Create a NEW demo database; refuses to replace an existing database."""
import re
from pathlib import Path
import server
import install_loans


def update_demo(name='CooperativeBankDemo'):
    """Refresh routines/reports and add missing indexes without replacing table data."""
    if not re.fullmatch(r'[A-Za-z][A-Za-z0-9_]{0,63}', name):
        raise ValueError('Invalid demo database name')
    source = Path(__file__).resolve().parent.parent / 'database'
    # USE fails if the target does not exist; this path never creates or resets it.
    server.query('USE `' + name + '`;')
    transactions = (source / '04_transactions.sql').read_text(encoding='utf-8-sig')
    transactions = re.sub(r'USE CooperativeBank\s*;', 'USE `' + name + '`;', transactions, flags=re.I)
    server.query('USE `' + name + '`;\nDROP PROCEDURE IF EXISTS Deposit;\n'
                 'DROP PROCEDURE IF EXISTS Withdraw;\nDROP PROCEDURE IF EXISTS Transfer;\n'
                 + transactions)
    install_loans.install(name)
    indexes = (source / '07_indexes.sql').read_text(encoding='utf-8-sig')
    indexes = re.sub(r'--[^\n]*', '', indexes)
    for statement in indexes.split(';'):
        statement = statement.strip()
        if not statement or re.fullmatch(r'USE\s+CooperativeBank', statement, re.I):
            continue
        match = re.fullmatch(r'CREATE INDEX (\w+)\s+ON (\w+)\s*\(([^)]+)\)', statement, re.I)
        if not match:
            raise ValueError('Unsupported index statement: ' + statement)
        index, table, columns = match.groups()
        expected = [column.strip() for column in columns.split(',')]
        existing = server.rows(
            'SELECT COLUMN_NAME FROM information_schema.STATISTICS WHERE TABLE_SCHEMA='
            + server.literal(name) + ' AND TABLE_NAME=' + server.literal(table)
            + ' AND INDEX_NAME=' + server.literal(index) + ' ORDER BY SEQ_IN_INDEX'
        )
        if existing:
            if [row['COLUMN_NAME'] for row in existing] != expected:
                raise ValueError('Existing index has a different definition: ' + index)
        else:
            server.query('USE `' + name + '`;' + statement + ';')
    print('Updated reports and indexes in ' + name + '; table data retained.')


def create_demo(name='CooperativeBankDemo'):
    if not re.fullmatch(r'[A-Za-z][A-Za-z0-9_]{0,63}', name):
        raise ValueError('Invalid demo database name')
    source = Path(__file__).resolve().parent.parent / 'database'
    # Validate all routine definitions before creating the database.
    install_loans.procedure_definitions()
    server.query('CREATE DATABASE `' + name + '`;')
    try:
        for filename in ['01_schema.sql', '02_constraints_triggers.sql', '02_account_opening.sql',
                         '02_loan_dates.sql', '03_seed_data.sql', '04_transactions.sql']:
            sql = (source / filename).read_text(encoding='utf-8-sig')
            sql = re.sub(r'CREATE DATABASE IF NOT EXISTS CooperativeBank\s*;', '', sql, flags=re.I)
            sql = re.sub(r'USE CooperativeBank\s*;', 'USE `' + name + '`;', sql, flags=re.I)
            server.query(sql)
        update_demo(name)
    except Exception:
        print('Setup stopped. The newly created database was retained for inspection; no reset was attempted.')
        raise
    print('Created ' + name + ' with sample data and all supported operation procedures.')


if __name__ == '__main__':
    import argparse
    import getpass
    import os
    import shutil
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--name', default='CooperativeBankDemo')
    parser.add_argument('--password', action='store_true')
    parser.add_argument('--update', action='store_true', help='Update routines, reports, and indexes in an existing database; retain table data')
    args = parser.parse_args()
    client = shutil.which('mysql') or r'C:\Program Files\MySQL\MySQL Server 8.0\bin\mysql.exe'
    server.MYSQL_ARGS = [client, '--login-path=local']
    if args.password:
        os.environ['MYSQL_PWD'] = getpass.getpass('MySQL root password (not saved): ')
        server.MYSQL_ARGS = [client, '--host=127.0.0.1', '--user=root']
    server.MYSQL_ARGS += ['--xml', '--batch', '--default-character-set=utf8mb4']
    if args.update:
        update_demo(args.name)
    else:
        create_demo(args.name)
