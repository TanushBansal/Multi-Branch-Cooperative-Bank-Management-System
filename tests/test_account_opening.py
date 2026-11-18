'Account-opening and privilege integration tests in a disposable database.'
import os
from pathlib import Path
import subprocess
import unittest
import uuid

ROOT = Path(__file__).resolve().parents[1]


class AccountOpeningTest(unittest.TestCase):
    @classmethod
    def run_sql(cls, sql, database=True, user=None, password=None, force=False):
        args = [os.environ.get("MYSQL_TEST_CLIENT", "mysql"),
                "--host=" + os.environ.get("MYSQL_TEST_HOST", "127.0.0.1"),
                "--port=" + os.environ.get("MYSQL_TEST_PORT", "3306"),
                "--user=" + (user or os.environ.get("MYSQL_TEST_USER", "root")),
                "--batch", "--skip-column-names", "--raw", "--connect-timeout=5"]
        if database:
            args.append("--database=" + cls.database)
        if force:
            args.append("--force")
        env = os.environ.copy()
        if password is not None:
            env["MYSQL_PWD"] = password
        return subprocess.run(args, input=sql, text=True, capture_output=True, env=env, timeout=60)

    @classmethod
    def execute(cls, sql, **kwargs):
        result = cls.run_sql(sql, **kwargs)
        if result.returncode or "ERROR " in result.stderr:
            raise AssertionError(result.stderr)
        return result.stdout.strip()

    @classmethod
    def setUpClass(cls):
        token = uuid.uuid4().hex
        cls.database = "cb_open_test_" + token
        cls.user = "cb_" + token[:20]
        cls.role = "cb_role_" + token[:20]
        cls.password = uuid.uuid4().hex + "!aA1"
        cls.counter = 100
        cls.execute("CREATE DATABASE " + cls.database, database=False)
        cls.addClassCleanup(cls.cleanup_database)
        for filename in ("01_schema.sql", "02_constraints_triggers.sql", "02_account_opening.sql", "04_transactions.sql"):
            sql = (ROOT / "database" / filename).read_text(encoding="utf-8")
            sql = sql.replace("CREATE DATABASE IF NOT EXISTS CooperativeBank;", "")
            sql = sql.replace("USE CooperativeBank;", "USE " + cls.database + ";")
            cls.execute(sql)
        cls.execute("INSERT INTO Bank VALUES (1,'Test'); "
                    "INSERT INTO Branch VALUES (1,1,'TEST0000001','Test',NULL); "
                    "INSERT INTO Customer (CustomerID,CustomerName,PAN) VALUES (1,'Test','ABCDE1234F')")
        cls.execute("CREATE ROLE '" + cls.role + "'", database=False)
        cls.addClassCleanup(lambda: cls.execute("DROP ROLE '" + cls.role + "'", database=False))
        access = (ROOT / "scripts/account_access.sql").read_text(encoding="utf-8")
        access = access.replace("cooperative_account_operator", cls.role).replace("CooperativeBank.", cls.database + ".")
        cls.execute(access)
        cls.execute(f"CREATE USER '{cls.user}'@'%' IDENTIFIED BY '{cls.password}'", database=False)
        cls.addClassCleanup(lambda: cls.execute(f"DROP USER '{cls.user}'@'%'", database=False))
        cls.execute(f"GRANT '{cls.role}' TO '{cls.user}'@'%'; "
                    f"SET DEFAULT ROLE '{cls.role}' TO '{cls.user}'@'%';", database=False)

    @classmethod
    def cleanup_database(cls):
        suffix = cls.database.removeprefix("cb_open_test_")
        if len(suffix) != 32 or any(c not in "0123456789abcdef" for c in suffix):
            raise AssertionError("Unexpected test database name")
        cls.execute("DROP DATABASE " + cls.database, database=False)

    def setUp(self):
        type(self).counter += 1
        self.account = self.counter

    def savings(self, account=None, customer=1, rate=4, minimum=100, amount=500, request=None):
        account = account or self.account
        request = request or "open-" + str(account)
        return f"CALL OpenSavingsAccount({account},1,{customer},'2026-01-01',{rate},{minimum},{amount},'{request}')"

    def assert_rejected_without_account(self, sql):
        result = self.run_sql(sql)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        for table in ("Account", "AccountHolder", "SavingsAccount", "CurrentAccount", "FixedDeposit", "BankTransaction"):
            self.assertEqual(self.execute(f"SELECT COUNT(*) FROM {table} WHERE AccountNo={self.account}"), "0")

    def test_open_all_types_through_restricted_role(self):
        account = self.account
        self.execute(self.savings(), user=self.user, password=self.password)
        self.execute(f"CALL OpenCurrentAccount({account+1000},1,1,'2026-01-01',100,500,'current-{account}')",
                     user=self.user, password=self.password)
        self.execute(f"CALL OpenFixedDeposit({account+2000},1,1,'2026-01-01','2027-01-01',1000,6,'fd-{account}')",
                     user=self.user, password=self.password)
        self.assertEqual(self.execute(f"SELECT COUNT(*) FROM AccountHolder WHERE AccountNo IN ({account},{account+1000},{account+2000})"), "3")
        self.assertEqual(self.execute(f"SELECT SUM(Amount) FROM BankTransaction WHERE AccountNo IN ({account},{account+1000},{account+2000}) AND Status='SUCCESS'"), "2000.00")
        for table, number in (("SavingsAccount",account),("CurrentAccount",account+1000),("FixedDeposit",account+2000)):
            self.assertEqual(self.execute(f"SELECT COUNT(*) FROM {table} WHERE AccountNo={number}"), "1")

    def test_late_failure_rolls_back_parent_subtype_and_holder(self):
        self.assert_rejected_without_account(self.savings(customer=999))
        self.assert_rejected_without_account(self.savings(rate=-1))
        self.assert_rejected_without_account(f"CALL OpenFixedDeposit({self.account},1,1,'2026-01-01','2025-01-01',1000,6,'invalid-date')")

    def test_duplicate_funding_request_rolls_back_new_account(self):
        self.execute(self.savings(account=self.account+1000, request='duplicate-opening'))
        self.assert_rejected_without_account(self.savings(request='duplicate-opening'))

    def test_invalid_amount_and_minimum_balance(self):
        for amount, minimum in ((-1,0),(0,100),(50,100),(1.001,0),(500,-1)):
            self.assert_rejected_without_account(self.savings(amount=amount, minimum=minimum))

    def test_zero_funded_savings_and_current(self):
        self.execute(self.savings(amount=0, minimum=0))
        self.execute(f"CALL OpenCurrentAccount({self.account+1000},1,1,'2026-01-01',0,0,NULL)")
        self.assertEqual(self.execute(f"SELECT COUNT(*) FROM BankTransaction WHERE AccountNo IN ({self.account},{self.account+1000})"), "0")

    def test_subtype_deletion_and_reassignment_blocked(self):
        self.execute(self.savings())
        self.execute(self.savings(account=self.account+1000))
        self.execute(f"CALL OpenCurrentAccount({self.account+2000},1,1,'2026-01-01',0,0,NULL)")
        self.execute(f"CALL OpenFixedDeposit({self.account+3000},1,1,'2026-01-01','2027-01-01',1000,6,'delete-fd-{self.account}')")
        for table, account in (("SavingsAccount",self.account),("CurrentAccount",self.account+2000),("FixedDeposit",self.account+3000)):
            for sql in (f"DELETE FROM {table} WHERE AccountNo={account}",
                        f"UPDATE {table} SET AccountNo={self.account+1000} WHERE AccountNo={account}"):
                result = self.run_sql(sql)
                self.assertNotEqual(result.returncode, 0)
            self.assertEqual(self.execute(f"SELECT COUNT(*) FROM {table} WHERE AccountNo={account}"), "1")

    def test_role_cannot_bypass_account_creation(self):
        for sql in (f"INSERT INTO Account (AccountNo,BranchID,AccountType,OpenedOn) VALUES ({self.account},1,'SAVINGS','2026-01-01')",
                    "DELETE FROM SavingsAccount", "UPDATE Account SET Balance=100", "TRUNCATE TABLE SavingsAccount"):
            result = self.run_sql(sql, user=self.user, password=self.password)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("denied", result.stderr)

    def test_role_can_only_create_transfers_through_procedure(self):
        self.execute(self.savings(), user=self.user, password=self.password)
        self.execute(self.savings(account=self.account+1000), user=self.user, password=self.password)
        self.execute(f"CALL Transfer({self.account},{self.account+1000},10,NULL,'role-transfer',@id)",
                     user=self.user, password=self.password)
        self.assertEqual(self.execute("SELECT COUNT(*) FROM TransferDetails d JOIN BankTransaction t "
                                     "USING(TransactionID) WHERE t.RequestID='role-transfer'"), '1')
        for sql in ("INSERT INTO BankTransaction (TransactionType,Amount,RequestID) VALUES ('TRANSFER',1,'bypass')",
                    "INSERT INTO TransferDetails (TransactionID,FromAccountNo,ToAccountNo) VALUES (999,1,2)",
                    "DELETE FROM TransferDetails", "UPDATE TransferDetails SET ToAccountNo=1",
                    "TRUNCATE TABLE TransferDetails"):
            result = self.run_sql(sql, user=self.user, password=self.password)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('denied', result.stderr)

    def test_call_inside_existing_transaction_preserves_caller_work(self):
        result = self.run_sql("START TRANSACTION; UPDATE Bank SET BankName='Uncommitted' WHERE BankID=1; "
                              + self.savings() + "; SELECT BankName FROM Bank WHERE BankID=1; ROLLBACK;", force=True)
        self.assertIn("Transaction characteristics can't be changed", result.stderr)
        self.assertEqual(result.stdout.strip(), "Uncommitted")
        self.assertEqual(self.execute("SELECT BankName FROM Bank WHERE BankID=1"), "Test")


if __name__ == '__main__':
    unittest.main()

