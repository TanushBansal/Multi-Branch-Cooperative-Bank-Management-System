"""Exercise actual MySQL procedures and HTTP endpoints in a disposable database."""
import json
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
    assert sum(o['available'] for o in config['operations']) == 7
    for table in config['tables']:
        assert get('/api/table?name=' + table)['columns']
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
    operate('ApplyLoan', ['1','1','PERSONAL','10000','Presentation test'])
    before = server.rows('SELECT Balance FROM Account WHERE AccountNo=1001')
    try:
        operate('Withdraw', ['1001','999999','ATM','web-reject'])
        raise AssertionError('Invalid withdrawal was accepted')
    except HTTPError as error:
        assert error.code == 400
    assert server.rows('SELECT Balance FROM Account WHERE AccountNo=1001') == before
    try:
        urlopen(Request(base + '/api/operate', data=b'{}'))
        raise AssertionError('Missing token was accepted')
    except HTTPError as error:
        assert error.code == 403
    print('PASS: 7 real operations, 21 table endpoints, static files, rejected withdrawal rollback, and request-token protection.')
finally:
    if httpd:
        httpd.shutdown()
        httpd.server_close()
    if created:
        server.query('DROP DATABASE `' + name + '`;')
