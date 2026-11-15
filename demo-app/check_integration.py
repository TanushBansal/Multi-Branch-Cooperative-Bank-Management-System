"""Exercise actual MySQL procedures and HTTP endpoints in a disposable database."""
import json
from pathlib import Path
import threading
import uuid
from urllib.request import Request, urlopen
from urllib.error import HTTPError
import server
import setup_demo

name = 'cb_web_test_' + uuid.uuid4().hex[:16]
server.MYSQL_ARGS = [r'C:\Program Files\MySQL\MySQL Server 8.0\bin\mysql.exe',
                     '--login-path=local', '--xml', '--batch', '--default-character-set=utf8mb4']
created = False
httpd = None
try:
    setup_demo.create_demo(name)
    created = True
    server.MYSQL_ARGS += ['--database=' + name]
    httpd = server.ThreadingHTTPServer(('127.0.0.1', 0), server.Handler)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    base = f'http://127.0.0.1:{httpd.server_port}'

    def get(path):
        with urlopen(base + path) as response:
            return json.load(response)

    config = get('/api/config')
    assert sum(o['available'] for o in config['operations']) == 12
    for table in config['tables']:
        assert get('/api/table?name=' + table)['columns']
    assert len(config['views']) == 10
    for view in config['views']:
        result = get('/api/table?name=' + view)
        assert result['columns'] and result['keys'] == server.VIEW_KEYS[view]
    statement = get('/api/table?name=v_customer_statement')
    identities = [tuple(row[k] for k in statement['keys']) for row in statement['rows']]
    assert len(identities) == len(set(identities))
    snapshot = {table: server.rows('SELECT * FROM `' + table + '`') for table in config['tables']}
    setup_demo.update_demo(name)
    setup_demo.update_demo(name)
    assert snapshot == {table: server.rows('SELECT * FROM `' + table + '`') for table in config['tables']}
    indexes = server.rows("SELECT DISTINCT INDEX_NAME FROM information_schema.STATISTICS "
                          "WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='BankTransaction' "
                          "AND INDEX_NAME IN ('ix_transaction_date','ix_transaction_account_date')")
    assert len(indexes) == 2
    for asset in ['/', '/app.js', '/style.css']:
        with urlopen(base + asset) as response:
            assert response.status == 200

    def operate(operation, values):
        spec = next(o for o in config['operations'] if o['name'] == operation)
        params = [p['PARAMETER_NAME'] for p in spec['parameters'] if p['PARAMETER_MODE'] == 'IN']
        request = Request(base + '/api/operate',
                          data=json.dumps({'operation':operation, 'values':dict(zip(params, values))}).encode(),
                          headers={'Content-Type':'application/json', 'X-Demo-Token':config['token']})
        with urlopen(request) as response:
            return json.load(response)

    initial = server.rows('SELECT Balance FROM Account WHERE AccountNo=1001')[0]['Balance']
    operate('Deposit', ['1001', '500', 'BRANCH', 'web-deposit'])
    assert server.rows('SELECT Balance FROM Account WHERE AccountNo=1001')[0]['Balance'] != initial
    operate('Withdraw', ['1001', '500', 'BRANCH', 'web-withdraw'])
    assert server.rows('SELECT Balance FROM Account WHERE AccountNo=1001')[0]['Balance'] == initial
    operate('Transfer', ['1001', '2001', '250', 'ONLINE', 'web-transfer'])
    operate('OpenSavingsAccount', ['7001','1','1','2026-11-15','4','100','500','web-saving'])
    operate('OpenCurrentAccount', ['7002','1','1','2026-11-15','100','500','web-current'])
    operate('OpenFixedDeposit', ['7003','1','1','2026-11-15','2027-11-15','500','6','web-fd'])
    application = operate('ApplyLoan', ['1','1','PERSONAL','10000','Presentation test'])
    application_id = application['results'][0][0]['ApplicationID']
    operate('LinkLoanGuarantor', [application_id, '1'])
    operate('ReviewLoan', [application_id, '1', 'APPROVED'])
    funded = operate('DisburseLoan', [application_id, '1001', '12', '3'])
    loan_id = funded['results'][0][0]['LoanID']
    operate('GenerateInstallments', [loan_id])
    assert len(server.rows('SELECT * FROM LoanInstallment WHERE LoanID=' + loan_id)) == 3
    repaid = operate('RepayLoan', [loan_id, '500'])
    payment_id = repaid['results'][0][0]['PaymentID']
    allocation = server.rows('SELECT LoanID, SUM(AllocatedAmount) AS Total FROM PaymentAllocation '
                             'WHERE PaymentID=' + payment_id + ' GROUP BY LoanID')[0]
    assert allocation == {'LoanID': loan_id, 'Total': '500.00'}
    remaining = repaid['results'][0][0]['RemainingAmount']
    operate('RepayLoan', [loan_id, remaining])
    assert server.rows('SELECT Status FROM Loan WHERE LoanID=' + loan_id)[0]['Status'] == 'CLOSED'
    rejected = operate('ApplyLoan', ['1','1','PERSONAL','1000','Rejection test'])
    reject_id = rejected['results'][0][0]['ApplicationID']
    operate('ReviewLoan', [reject_id, '1', 'REJECTED'])
    try:
        operate('DisburseLoan', [reject_id, '1001', '12', '3'])
        raise AssertionError('Rejected application was disbursed')
    except HTTPError as error:
        assert error.code == 400
    before = server.rows('SELECT Balance FROM Account WHERE AccountNo=1001')
    try:
        operate('Withdraw', ['1001','999999','ATM','web-reject'])
        raise AssertionError('Invalid withdrawal was accepted')
    except HTTPError as error:
        assert error.code == 400
    assert server.rows('SELECT Balance FROM Account WHERE AccountNo=1001') == before
    checks = (Path(__file__).resolve().parent.parent / 'tests' / 'report_views_checks.sql').read_text()
    checks = checks.replace('USE CooperativeBank;', 'USE `' + name + '`;')
    assert not any(server.query(checks)), 'Reporting checks found inconsistencies'
    try:
        urlopen(Request(base + '/api/operate', data=b'{}'))
        raise AssertionError('Missing token was accepted')
    except HTTPError as error:
        assert error.code == 403
    print('PASS: 12 operations, 21 tables, 10 views, reporting checks, both indexes, repeatable updates preserving data, rollback, and token protection.')
finally:
    if httpd:
        httpd.shutdown()
        httpd.server_close()
    if created:
        server.query('DROP DATABASE `' + name + '`;')
