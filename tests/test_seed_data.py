"""Validate demo data in a disposable database, using the real schema/triggers.

Run: python -m unittest discover -s tests -p test_seed_data.py -v
Uses the same MYSQL_TEST_CLIENT/HOST/PORT/USER and MYSQL_PWD settings as
test_transactions.py. CooperativeBank is never modified by these tests.
"""

from decimal import Decimal, ROUND_HALF_UP
import os
from pathlib import Path
import subprocess
import unittest
import uuid


ROOT = Path(__file__).resolve().parents[1]


class SeedDataTest(unittest.TestCase):
    @classmethod
    def run_sql(cls, sql, database=True):
        args = [os.environ.get("MYSQL_TEST_CLIENT", "mysql"),
                "--host=" + os.environ.get("MYSQL_TEST_HOST", "127.0.0.1"),
                "--port=" + os.environ.get("MYSQL_TEST_PORT", "3306"),
                "--user=" + os.environ.get("MYSQL_TEST_USER", "root"),
                "--batch", "--skip-column-names", "--raw", "--connect-timeout=5"]
        if database:
            args.append("--database=" + cls.database)
        return subprocess.run(args, input=sql, text=True, capture_output=True, timeout=60)

    @classmethod
    def execute(cls, sql, **kwargs):
        result = cls.run_sql(sql, **kwargs)
        if result.returncode or "ERROR " in result.stderr:
            raise AssertionError(result.stderr)
        return result.stdout.strip()

    @classmethod
    def load_file(cls, filename):
        return (ROOT / "database" / filename).read_text(encoding="utf-8").replace(
            "CREATE DATABASE IF NOT EXISTS CooperativeBank;", "").replace(
            "USE CooperativeBank;", "USE " + cls.database + ";")

    @classmethod
    def setUpClass(cls):
        cls.database = "cb_seed_test_" + uuid.uuid4().hex
        cls.execute("CREATE DATABASE " + cls.database, database=False)
        cls.addClassCleanup(cls.drop_database)
        for filename in ("01_schema.sql", "02_constraints_triggers.sql", "03_seed_data.sql"):
            cls.execute(cls.load_file(filename))

    @classmethod
    def drop_database(cls):
        suffix = cls.database.removeprefix("cb_seed_test_")
        if len(suffix) != 32 or any(c not in "0123456789abcdef" for c in suffix):
            raise AssertionError("Unexpected test database name")
        cls.execute("DROP DATABASE " + cls.database, database=False)

    def assert_no_rows(self, sql):
        self.assertEqual(self.execute(sql), "")

    def test_all_tables_populated(self):
        tables = self.execute("SHOW TABLES").splitlines()
        self.assertEqual(len(tables), 21)
        for table in tables:
            with self.subTest(table=table):
                self.assertGreater(int(self.execute(f"SELECT COUNT(*) FROM `{table}`")), 0)

    def test_balances_reconcile_with_successful_history(self):
        self.assert_no_rows("""
            WITH movements AS (
                SELECT AccountNo,
                    CASE WHEN TransactionType IN ('DEPOSIT','LOAN_DISBURSEMENT')
                        THEN Amount ELSE -Amount END AS Delta
                FROM BankTransaction WHERE Status='SUCCESS' AND AccountNo IS NOT NULL
                UNION ALL
                SELECT d.FromAccountNo,-t.Amount FROM TransferDetails d
                    JOIN BankTransaction t USING(TransactionID) WHERE t.Status='SUCCESS'
                UNION ALL
                SELECT d.ToAccountNo,t.Amount FROM TransferDetails d
                    JOIN BankTransaction t USING(TransactionID) WHERE t.Status='SUCCESS'
            )
            SELECT a.AccountNo FROM Account a LEFT JOIN movements m USING(AccountNo)
            GROUP BY a.AccountNo,a.Balance HAVING a.Balance<>COALESCE(SUM(m.Delta),0);
        """)

    def test_account_ownership_specializations_and_roles(self):
        self.assert_no_rows("""
            SELECT a.AccountNo FROM Account a
            LEFT JOIN SavingsAccount s USING(AccountNo)
            LEFT JOIN CurrentAccount c USING(AccountNo)
            LEFT JOIN FixedDeposit f USING(AccountNo)
            WHERE (s.AccountNo IS NOT NULL)+(c.AccountNo IS NOT NULL)+(f.AccountNo IS NOT NULL)<>1
               OR (a.AccountType='SAVINGS' AND s.AccountNo IS NULL)
               OR (a.AccountType='CURRENT' AND c.AccountNo IS NULL)
               OR (a.AccountType='FD' AND f.AccountNo IS NULL)
               OR NOT EXISTS (SELECT 1 FROM AccountHolder h WHERE h.AccountNo=a.AccountNo);
            SELECT EmployeeID FROM Manager JOIN Clerk USING(EmployeeID);
        """)
        self.assertEqual(self.execute("SELECT COUNT(*) FROM AccountHolder WHERE AccountNo=3002"), "2")
        self.assertEqual(self.execute("SELECT COUNT(*) FROM Nominee WHERE AccountNo=1001"), "2")

    def test_transfer_details_and_reviewers(self):
        self.assert_no_rows("""
            SELECT t.TransactionID FROM BankTransaction t
            LEFT JOIN TransferDetails d USING(TransactionID)
            WHERE (t.TransactionType='TRANSFER' AND d.TransactionID IS NULL)
               OR (t.TransactionType<>'TRANSFER' AND d.TransactionID IS NOT NULL);
            SELECT a.ApplicationID FROM LoanApplication a JOIN Employee e ON e.EmployeeID=a.ReviewedBy
            WHERE e.BranchID<>a.BranchID;
        """)
        self.assertEqual(self.execute("SELECT GROUP_CONCAT(DISTINCT Status ORDER BY Status) "
                                     "FROM BankTransaction"), "PENDING,SUCCESS,FAILED")

    def test_loans_and_disbursements(self):
        self.assert_no_rows("""
            SELECT l.LoanID FROM Loan l JOIN LoanApplication a USING(ApplicationID)
            LEFT JOIN BankTransaction t ON t.TransactionID=l.DisbursementTransactionID
            WHERE a.Status<>'APPROVED'
               OR NOT EXISTS (SELECT 1 FROM ApplicationGuarantor g WHERE g.ApplicationID=a.ApplicationID)
               OR NOT EXISTS (SELECT 1 FROM AccountHolder h
                    WHERE h.AccountNo=l.PayoutAccountNo AND h.CustomerID=a.CustomerID)
               OR (l.Status='SANCTIONED' AND l.DisbursementTransactionID IS NOT NULL)
               OR (l.Status<>'SANCTIONED' AND l.DisbursementTransactionID IS NULL)
               OR (t.TransactionID IS NOT NULL AND
                    (t.Status<>'SUCCESS' OR t.TransactionType<>'LOAN_DISBURSEMENT'
                     OR t.Amount<>l.SanctionAmount OR t.AccountNo<>l.PayoutAccountNo));
        """)

    def test_emi_schedule_math(self):
        loans = self.execute("SELECT LoanID,SanctionAmount,InterestRate,TenureMonths "
                             "FROM Loan WHERE DisbursementTransactionID IS NOT NULL").splitlines()
        cents = Decimal("0.01")
        for row in loans:
            loan_id, principal, rate, months = row.split("\t")
            balance = Decimal(principal)
            monthly_rate = Decimal(rate) / 1200
            count = int(months)
            emi = balance / count if not monthly_rate else (
                balance * monthly_rate / (1 - (1 + monthly_rate) ** -count))
            emi = emi.quantize(cents, rounding=ROUND_HALF_UP)
            schedule = self.execute("SELECT InstallmentNo,PrincipalDue,InterestDue "
                                    f"FROM LoanInstallment WHERE LoanID={loan_id} "
                                    "ORDER BY InstallmentNo").splitlines()
            self.assertEqual(len(schedule), count)
            for number, installment in enumerate(schedule, 1):
                actual_number, principal_due, interest_due = installment.split("\t")
                interest = (balance * monthly_rate).quantize(cents, rounding=ROUND_HALF_UP)
                expected_principal = balance if number == count else emi - interest
                self.assertEqual(int(actual_number), number)
                self.assertEqual(Decimal(interest_due), interest)
                self.assertEqual(Decimal(principal_due), expected_principal)
                balance -= Decimal(principal_due)
            self.assertEqual(balance, 0)
        self.assertEqual(self.execute("SELECT COUNT(*) FROM LoanInstallment WHERE LoanID=3"), "0")

    def test_repayments_and_allocations(self):
        self.assert_no_rows("""
            SELECT r.PaymentID FROM Repayment r JOIN BankTransaction t USING(TransactionID)
            WHERE t.Status<>'SUCCESS' OR t.TransactionType<>'LOAN_REPAYMENT'
               OR t.Amount<>r.Amount OR t.TransactionDate<>r.PaidAt;
            SELECT p.PaymentID FROM PaymentAllocation p
            JOIN Repayment r USING(PaymentID) JOIN LoanInstallment i USING(InstallmentID)
            WHERE r.LoanID<>i.LoanID;
            SELECT r.PaymentID FROM Repayment r LEFT JOIN PaymentAllocation p USING(PaymentID)
            GROUP BY r.PaymentID,r.Amount HAVING COALESCE(SUM(p.AllocatedAmount),0)<>r.Amount;
            SELECT i.InstallmentID FROM LoanInstallment i LEFT JOIN PaymentAllocation p USING(InstallmentID)
            GROUP BY i.InstallmentID,i.PrincipalDue,i.InterestDue
            HAVING COALESCE(SUM(p.AllocatedAmount),0)>i.PrincipalDue+i.InterestDue;
            SELECT l.LoanID FROM Loan l JOIN LoanInstallment i USING(LoanID)
            LEFT JOIN PaymentAllocation p USING(InstallmentID) WHERE l.Status='CLOSED'
            GROUP BY l.LoanID HAVING SUM(i.PrincipalDue+i.InterestDue)<>SUM(p.AllocatedAmount);
        """)

    def test_seed_reexecution_fails_without_changing_data(self):
        def snapshot():
            return self.execute("SELECT AccountNo,Balance FROM Account ORDER BY AccountNo;"
                                "SELECT COUNT(*) FROM BankTransaction; SELECT COUNT(*) FROM Loan;")
        before = snapshot()
        result = self.run_sql(self.load_file("03_seed_data.sql"))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Duplicate entry", result.stderr)
        self.assertEqual(before, snapshot())


if __name__ == "__main__":
    unittest.main()
