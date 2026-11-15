"""Install the project's loan routines into the selected demo database."""
from pathlib import Path
import re
import server

LOAN_PROCEDURES = (
    'ApplyLoan', 'ReviewLoan', 'DisburseLoan', 'GenerateInstallments', 'RepayLoan'
)


def procedure_definitions():
    source = Path(__file__).resolve().parent.parent / 'database' / '05_loans.sql'
    sql = source.read_text(encoding='utf-8-sig')
    definitions = {}
    for name in LOAN_PROCEDURES:
        match = re.search(
            r'CREATE\s+PROCEDURE\s+' + name + r'\s*\(.*?\bEND\s*\$\$',
            sql, re.S | re.I
        )
        if not match:
            raise ValueError('Cannot locate procedure: ' + name)
        definitions[name] = match.group(0)

    definitions['LinkLoanGuarantor'] = '''CREATE PROCEDURE LinkLoanGuarantor(
    IN p_application_id INT,
    IN p_guarantor_id INT
)
BEGIN
    INSERT INTO ApplicationGuarantor (ApplicationID, GuarantorID)
    VALUES (p_application_id, p_guarantor_id);
    SELECT 'Guarantor linked successfully' AS Message;
END $$'''
    return definitions


def install(database):
    if not re.fullmatch(r'[A-Za-z][A-Za-z0-9_]{0,63}', database):
        raise ValueError('Invalid database name')
    definitions = procedure_definitions()
    for name, definition in definitions.items():
        server.query(
            'USE `' + database + '`;\nDROP PROCEDURE IF EXISTS `' + name + '`;\n'
            'DELIMITER $$\n' + definition + '\nDELIMITER ;\n'
        )
    print('Installed five loan procedures and guarantor linking in ' + database + '.')


if __name__ == '__main__':
    import argparse
    import getpass
    import os
    import shutil
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--database', default='CooperativeBankDemo')
    parser.add_argument('--password', action='store_true')
    args = parser.parse_args()
    client = shutil.which('mysql') or r'C:\Program Files\MySQL\MySQL Server 8.0\bin\mysql.exe'
    server.MYSQL_ARGS = [client, '--login-path=local']
    if args.password:
        os.environ['MYSQL_PWD'] = getpass.getpass('MySQL root password (not saved): ')
        server.MYSQL_ARGS = [client, '--host=127.0.0.1', '--user=root']
    server.MYSQL_ARGS += ['--xml', '--batch', '--default-character-set=utf8mb4']
    install(args.database)
