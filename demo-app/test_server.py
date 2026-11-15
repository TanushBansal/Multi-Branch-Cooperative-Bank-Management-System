import unittest
from unittest.mock import patch
from types import SimpleNamespace
import server


class DemoTests(unittest.TestCase):
    def test_values_cannot_become_sql(self):
        attack = "'); DROP TABLE Account; --\\雪"
        encoded = server.literal(attack)
        self.assertNotIn('DROP', encoded)
        self.assertIn(attack.encode().hex(), encoded)

    def test_multiple_result_sets_and_null(self):
        xml = '<?xml version="1.0"?><resultset><row><field name="ID">42</field></row></resultset>'
        xml += '<?xml version="1.0"?><resultset><row><field name="Empty" /></row></resultset>'
        with patch('server.subprocess.run', return_value=SimpleNamespace(returncode=0, stdout=xml)):
            self.assertEqual(server.query('CALL Test();'), [[{'ID':'42'}],[{'Empty':None}]])

    def test_missing_operation_does_not_execute(self):
        with patch('server.catalog', return_value=[]), patch('server.query') as query:
            with self.assertRaises(ValueError):
                server.run_operation({'operation':'DROP TABLE Account', 'values':{}})
            query.assert_not_called()

    def test_output_parameters_and_input_quoting(self):
        catalog = [{'name':'Deposit','available':True,'parameters':[
            {'PARAMETER_NAME':'amount','PARAMETER_MODE':'IN'},
            {'PARAMETER_NAME':'transaction','PARAMETER_MODE':'OUT'}]}]
        with patch('server.catalog', return_value=catalog), patch('server.query', return_value=[]) as query:
            server.run_operation({'operation':'Deposit','values':{'amount':'500.00'}})
            sql = query.call_args.args[0]
            self.assertIn('SET @out_1=NULL;', sql)
            self.assertIn('CALL `Deposit`(CONVERT(', sql)
            self.assertIn('SELECT @out_1 AS `transaction`', sql)

    def test_database_error_is_not_success(self):
        with patch('server.subprocess.run', return_value=SimpleNamespace(returncode=1, stderr='Insufficient funds')):
            with self.assertRaisesRegex(ValueError, 'Insufficient funds'):
                server.query('CALL Withdraw();')


if __name__ == '__main__':
    unittest.main()
