"""Local presentation app. Python standard library + existing MySQL CLI only."""
import argparse
import getpass
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import subprocess
import xml.etree.ElementTree as ET
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs
from reports import REPORTS, expand_sql

ROOT = Path(__file__).resolve().parent
TOKEN = secrets.token_urlsafe(32)
TABLES = 'Bank Branch Employee Manager Clerk Customer Account AccountHolder Nominee SavingsAccount CurrentAccount FixedDeposit BankTransaction TransferDetails LoanApplication Guarantor ApplicationGuarantor Loan LoanInstallment Repayment PaymentAllocation'.split()
# Parameters are obtained from the installed routines, preserving their SQL order.
OPERATIONS = {
    'Deposit': 'Banking', 'Withdraw': 'Banking', 'Transfer': 'Banking',
    'OpenSavingsAccount': 'Banking', 'OpenCurrentAccount': 'Banking',
    'OpenFixedDeposit': 'Banking', 'ApplyLoan': 'Loans',
    'LinkLoanGuarantor': 'Loans', 'ReviewLoan': 'Loans',
    'DisburseLoan': 'Loans', 'GenerateInstallments': 'Loans', 'RepayLoan': 'Loans',
}
MYSQL_ARGS = []


def literal(value):
    if value is None:
        return 'NULL'
    return "CONVERT(X'%s' USING utf8mb4)" % str(value).encode('utf-8').hex()


def query(sql):
    result = subprocess.run(MYSQL_ARGS, input=sql, text=True, encoding='utf-8',
                            capture_output=True)  # Never retry a financial operation automatically.
    if result.returncode:
        raise ValueError(result.stderr.strip())
    xml = re.sub(r'<\?xml[^>]*\?>', '', result.stdout)
    if not xml.strip():
        return []
    root = ET.fromstring('<results>' + xml + '</results>')
    return [[{f.attrib['name']: f.text for f in row} for row in rs.findall('row')]
            for rs in root.findall('resultset')]


def rows(sql):
    result = query(sql)
    return result[0] if result else []


def catalog():
    installed = {r['ROUTINE_NAME'] for r in rows(
        "SELECT ROUTINE_NAME FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA=DATABASE() AND ROUTINE_TYPE='PROCEDURE'")}
    parameters = rows("SELECT SPECIFIC_NAME,PARAMETER_NAME,PARAMETER_MODE,DATA_TYPE,CHARACTER_MAXIMUM_LENGTH "
                      "FROM information_schema.PARAMETERS WHERE SPECIFIC_SCHEMA=DATABASE() ORDER BY SPECIFIC_NAME,ORDINAL_POSITION")
    return [{'name': name, 'section': section, 'available': name in installed,
             'parameters': [p for p in parameters if p['SPECIFIC_NAME'] == name]}
            for name, section in OPERATIONS.items()]


def run_operation(data):
    operation = next((o for o in catalog() if o['name'] == data.get('operation')), None)
    if not operation or not operation['available']:
        raise ValueError('This procedure is not installed in the selected database.')
    supplied = data.get('values', {})
    args, output, init = [], [], []
    for i, p in enumerate(operation['parameters']):
        name = p['PARAMETER_NAME']
        if p['PARAMETER_MODE'] != 'IN':
            variable = '@out_' + str(i)
            init.append('SET ' + variable + '=NULL;')
            args.append(variable)
            output.append(variable + ' AS `' + name.replace('`', '``') + '`')
        else:
            if name not in supplied or not str(supplied[name]).strip():
                raise ValueError('Missing value: ' + name)
            args.append(literal(supplied[name]))
    sql = ''.join(init) + 'CALL `' + operation['name'] + '`(' + ','.join(args) + ');'
    if output:
        sql += 'SELECT ' + ','.join(output) + ';'
    return query(sql)


class Handler(BaseHTTPRequestHandler):
    def send(self, status, body, content_type='application/json'):
        payload = (json.dumps(body) if content_type == 'application/json' else body).encode('utf-8')
        self.send_response(status)
        self.send_header('Content-Type', content_type + '; charset=utf-8')
        self.send_header('Content-Length', str(len(payload)))
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('Content-Security-Policy', "default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self'; frame-ancestors 'none'")
        self.end_headers()
        self.wfile.write(payload)

    def valid_host(self):
        return self.headers.get('Host') in {f'localhost:{self.server.server_port}', f'127.0.0.1:{self.server.server_port}'}

    def do_GET(self):
        if not self.valid_host():
            return self.send(403, {'error': 'Local access only'})
        parsed = urlparse(self.path)
        try:
            if parsed.path == '/api/config':
                return self.send(200, {'token': TOKEN, 'operations': catalog(), 'tables': TABLES,
                                      'reports': list(REPORTS),
                                      'database': rows('SELECT DATABASE() AS name')[0]['name']})
            if parsed.path == '/api/table':
                params = parse_qs(parsed.query)
                table = params.get('name', ['Account'])[0]
                if table not in TABLES and table not in REPORTS:
                    raise ValueError('Unknown table')
                page = max(0, int(params.get('page', ['0'])[0]))
                if table in REPORTS:
                    report = REPORTS[table]
                    columns = report['columns']
                    keys = report['keys']
                    source = '(' + report['sql'] + ') AS report_data'
                else:
                    metadata = rows('SHOW COLUMNS FROM `' + table + '`')
                    columns = [c['Field'] for c in metadata]
                    keys = [c['Field'] for c in metadata if c['Key'] == 'PRI']
                    source = '`' + table + '`'
                order = (['AccountNo', 'TransactionDate', 'TransactionID']
                         if table == 'account_statement' else
                         ['CustomerID', 'AccountNo', 'TransactionDate', 'TransactionID']
                         if table == 'customer_statement' else keys)
                ordering = ' ORDER BY ' + ','.join('`' + c + '`' for c in order) if order else ''
                records = rows('SELECT * FROM ' + source + ordering + ' LIMIT 50 OFFSET ' + str(page * 50))
                total = rows('SELECT COUNT(*) AS total FROM ' + source)[0]['total']
                return self.send(200, {'columns': columns,
                                      'keys': keys, 'rows': records, 'total': total})
            files = {'/': ('index.html', 'text/html'), '/app.js': ('app.js', 'text/javascript'), '/style.css': ('style.css', 'text/css')}
            if parsed.path not in files:
                return self.send(404, {'error': 'Not found'})
            filename, mime = files[parsed.path]
            self.send(200, (ROOT / filename).read_text(encoding='utf-8'), mime)
        except (ValueError, OSError, ET.ParseError) as error:
            self.send(400, {'error': str(error)})

    def do_POST(self):
        if not self.valid_host() or self.headers.get('X-Demo-Token') != TOKEN:
            return self.send(403, {'error': 'Reload this local app before continuing.'})
        if self.path != '/api/operate':
            return self.send(404, {'error': 'Not found'})
        try:
            size = int(self.headers.get('Content-Length', '0'))
            if size <= 0 or size > 16384:
                raise ValueError('Invalid request size')
            data = json.loads(self.rfile.read(size))
            if not isinstance(data, dict) or not isinstance(data.get('values'), dict):
                raise ValueError('Invalid operation')
            self.send(200, {'results': run_operation(data)})
        except (ValueError, OSError, ET.ParseError) as error:
            self.send(400, {'error': str(error)})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--database', default='CooperativeBank')
    parser.add_argument('--port', type=int, default=8080)
    parser.add_argument('--password', action='store_true', help='Prompt once for a password instead of using login-path=local')
    parser.add_argument('--user', default='root')
    parser.add_argument('--mysql', default=shutil.which('mysql') or r'C:\Program Files\MySQL\MySQL Server 8.0\bin\mysql.exe')
    opts = parser.parse_args()
    global MYSQL_ARGS
    MYSQL_ARGS = [opts.mysql]
    if opts.password:
        os.environ['MYSQL_PWD'] = getpass.getpass('MySQL password (not saved): ')
        MYSQL_ARGS += ['--host=127.0.0.1', '--user=' + opts.user]
    else:
        MYSQL_ARGS += ['--login-path=local']
    MYSQL_ARGS += ['--database=' + opts.database, '--xml', '--batch', '--default-character-set=utf8mb4']
    try:
        rows('SELECT 1')
    except (OSError, ValueError) as error:
        raise SystemExit('Cannot connect to MySQL: ' + str(error) + '\nTry: python demo-app/server.py --password')
    server = ThreadingHTTPServer(('127.0.0.1', opts.port), Handler)
    print(f'Bank demo: http://127.0.0.1:{opts.port}  |  Database: {opts.database}\nCtrl+C to stop.', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == '__main__':
    main()
