'Loan procedure integration tests. Run from the repo root with unittest discover.'
from concurrent.futures import ThreadPoolExecutor
from decimal import Decimal
import os
from pathlib import Path
import subprocess
import time
import unittest
import uuid


ROOT = Path(__file__).resolve().parents[1]
BUILD_FILES = (
    "01_schema.sql",
    "02_account_opening.sql",
    "02_constraints_triggers.sql",
    "02_loan_dates.sql",
    "03_seed_data.sql",
    "04_transactions.sql",
    "05_loans.sql",
)


class LoanTests(unittest.TestCase):
    @classmethod
    def client(cls, use_database=True):
        args = [
            os.environ.get("MYSQL_TEST_CLIENT", "mysql"),
            "--host=" + os.environ.get("MYSQL_TEST_HOST", "127.0.0.1"),
            "--port=" + os.environ.get("MYSQL_TEST_PORT", "3306"),
            "--user=" + os.environ.get("MYSQL_TEST_USER", "root"),
            "--batch", "--raw", "--skip-column-names", "--unbuffered",
            "--connect-timeout=5",
        ]
        if use_database:
            args.append("--database=" + cls.database)
        return args

    @classmethod
    def run_sql(cls, statement, use_database=True):
        return subprocess.run(
            cls.client(use_database), input=statement, text=True,
            encoding="utf-8", capture_output=True, timeout=60,
        )

    @classmethod
    def sql(cls, statement, use_database=True):
        result = cls.run_sql(statement, use_database)
        if result.returncode:
            raise AssertionError(result.stderr.strip())
        return result.stdout.strip()

    @classmethod
    def setUpClass(cls):
        cls.database = "cb_loans_test_" + uuid.uuid4().hex
        cls.sql("CREATE DATABASE " + cls.database, use_database=False)
        cls.addClassCleanup(cls.sql, "DROP DATABASE " + cls.database, False)
        for filename in BUILD_FILES:
            statement = (ROOT / "database" / filename).read_text(encoding="utf-8-sig")
            statement = statement.replace("CREATE DATABASE IF NOT EXISTS CooperativeBank;", "")
            cls.sql(statement.replace("USE CooperativeBank;", ""))

    def assert_rejected(self, statement, message):
        result = self.run_sql(statement)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(message, result.stderr)

    def new_loan(self):
        application = int(self.sql(
            "CALL ApplyLoan(1,1,'PERSONAL',5000,'Integration test');"
        ).split("\t")[0])
        self.sql(f"""
            INSERT INTO ApplicationGuarantor (ApplicationID, GuarantorID)
            VALUES ({application},1);
            CALL ReviewLoan({application},1,'APPROVED');
        """)
        loan = int(self.sql(
            f"CALL DisburseLoan({application},1001,0,3);"
        ).split("\t")[0])
        self.sql(f"CALL GenerateInstallments({loan});")
        return loan

    def pending_application(self):
        return int(self.sql("CALL ApplyLoan(1,1,'PERSONAL',5000,'Pipeline test');").split('\t')[0])

    def test_approval_is_separate_from_disbursement(self):
        application = self.pending_application()
        before = self.sql('SELECT Balance FROM Account WHERE AccountNo=1001;')
        self.assert_rejected(f"CALL ReviewLoan({application},1,'APPROVED');", 'guarantor')
        self.sql(f'INSERT INTO ApplicationGuarantor VALUES ({application},1);')
        self.assert_rejected(f"CALL ReviewLoan({application},3,'APPROVED');", 'different branch')
        self.sql(f"CALL ReviewLoan({application},1,'APPROVED');")
        self.assertEqual(self.sql(f'SELECT Status FROM LoanApplication WHERE ApplicationID={application};'), 'APPROVED')
        self.assertEqual(self.sql(f'SELECT COUNT(*) FROM Loan WHERE ApplicationID={application};'), '0')
        self.assertEqual(self.sql('SELECT Balance FROM Account WHERE AccountNo=1001;'), before)
        loan = int(self.sql(f'CALL DisburseLoan({application},1001,12,3);').split('\t')[0])
        self.assertEqual(self.sql(f'SELECT ApplicationID,Status FROM Loan WHERE LoanID={loan};'), f'{application}\tACTIVE')

    def test_disbursement_rejects_invalid_accounts_without_moving_funds(self):
        application = self.pending_application()
        self.sql(f'INSERT INTO ApplicationGuarantor VALUES ({application},1);')
        self.sql(f"CALL ReviewLoan({application},1,'APPROVED');")
        before = self.sql('SELECT AccountNo,Balance FROM Account ORDER BY AccountNo; SELECT COUNT(*) FROM BankTransaction;')
        for account, error in [(999999,'does not exist'), (1002,'does not belong'),
                               (1004,'not active'), (1003,'Savings or Current')]:
            self.assert_rejected(f'CALL DisburseLoan({application},{account},12,3);', error)
            self.assertEqual(self.sql('SELECT AccountNo,Balance FROM Account ORDER BY AccountNo; SELECT COUNT(*) FROM BankTransaction;'), before)
        self.assertEqual(self.sql(f'SELECT COUNT(*) FROM Loan WHERE ApplicationID={application};'), '0')

    def test_repayment_preserves_minimum_balance_and_rejects_fractional_cents(self):
        loan = self.new_loan()
        self.sql("CALL Withdraw(1001,(SELECT Balance-1100 FROM Account WHERE AccountNo=1001),'BRANCH','loan-minimum-test',@tx);")
        before = self.sql('SELECT Balance FROM Account WHERE AccountNo=1001; SELECT COUNT(*) FROM Repayment; SELECT COUNT(*) FROM BankTransaction;')
        self.assert_rejected(f'CALL RepayLoan({loan},500);', 'minimum balance')
        self.assert_rejected(f'CALL RepayLoan({loan},0.001);', 'whole cents')
        self.assert_rejected("CALL ApplyLoan(1,1,'PERSONAL',1000.001,'Rounding test');", 'whole cents')
        self.assertEqual(self.sql('SELECT Balance FROM Account WHERE AccountNo=1001; SELECT COUNT(*) FROM Repayment; SELECT COUNT(*) FROM BankTransaction;'), before)

    def test_loan_calls_preserve_an_existing_caller_transaction(self):
        calls = ["ApplyLoan(1,1,'PERSONAL',1000,'Nested test')",
                 "ReviewLoan(99999,1,'APPROVED')", 'DisburseLoan(99999,1001,12,3)',
                 'GenerateInstallments(99999)', 'RepayLoan(99999,1)']
        before = self.sql('SELECT Phone FROM Customer WHERE CustomerID=1;')
        for call in calls:
            with self.subTest(call=call):
                result = subprocess.run(self.client()+['--force'], input=(
                    "START TRANSACTION; UPDATE Customer SET Phone='nested-probe' WHERE CustomerID=1; "
                    'CALL '+call+'; SELECT Phone FROM Customer WHERE CustomerID=1; ROLLBACK;'),
                    text=True, encoding='utf-8', capture_output=True, timeout=60)
                self.assertIn("Transaction characteristics can't be changed", result.stderr)
                self.assertEqual(result.stdout.strip(), 'nested-probe')
                self.assertEqual(self.sql('SELECT Phone FROM Customer WHERE CustomerID=1;'), before)

    def test_concurrent_disbursements_credit_once(self):
        application = self.pending_application()
        self.sql(f'INSERT INTO ApplicationGuarantor VALUES ({application},1);')
        self.sql(f"CALL ReviewLoan({application},1,'APPROVED');")
        before = Decimal(self.sql('SELECT Balance FROM Account WHERE AccountNo=1001;'))
        with ThreadPoolExecutor(max_workers=2) as workers:
            results = list(workers.map(lambda _: self.run_sql(f'CALL DisburseLoan({application},1001,12,3);'), range(2)))
        self.assertEqual(sum(result.returncode == 0 for result in results), 1)
        self.assertEqual(Decimal(self.sql('SELECT Balance FROM Account WHERE AccountNo=1001;')), before+5000)
        self.assertEqual(self.sql(f'SELECT COUNT(*) FROM Loan WHERE ApplicationID={application};'), '1')

    def test_fund_seeded_sanction_once_and_generate_schedule(self):
        self.assert_rejected("CALL DisburseLoan(3,3002,8,6);", "must match the sanction")
        self.assertEqual(self.sql("SELECT Status FROM Loan WHERE LoanID=3;"), "SANCTIONED")
        before = Decimal(self.sql("SELECT Balance FROM Account WHERE AccountNo=3002;"))

        self.assertEqual(self.sql("CALL DisburseLoan(3,3002,9,6);").split("\t")[:2],
                         ["3", "30000.00"])
        self.assert_rejected("CALL DisburseLoan(3,3002,9,6);", "already been disbursed")
        self.assertEqual(Decimal(self.sql("SELECT Balance FROM Account WHERE AccountNo=3002;")),
                         before + Decimal("30000"))
        self.assertEqual(self.sql("""
            SELECT l.LoanID,l.Status,l.SanctionAmount,t.Amount,t.TransactionType,t.Status
            FROM Loan l JOIN BankTransaction t ON t.TransactionID=l.DisbursementTransactionID
            WHERE l.ApplicationID=3;
        """), "3\tACTIVE\t30000.00\t30000.00\tLOAN_DISBURSEMENT\tSUCCESS")

        self.sql("CALL GenerateInstallments(3);")
        self.assert_rejected("CALL GenerateInstallments(3);", "already generated")
        self.assertEqual(self.sql("""
            SELECT COUNT(*),SUM(i.PrincipalDue),
                   MIN(i.DueDate)=DATE_ADD(DATE(t.TransactionDate),INTERVAL 1 MONTH)
            FROM LoanInstallment i JOIN Loan l ON l.LoanID=i.LoanID
            JOIN BankTransaction t ON t.TransactionID=l.DisbursementTransactionID
            WHERE i.LoanID=3 GROUP BY t.TransactionDate;
        """), "6\t30000.00\t1")

    def test_partial_repayment_allocates_oldest_first_then_closes(self):
        loan = self.new_loan()
        self.sql(f"CALL RepayLoan({loan},1800);")
        self.assertEqual(self.sql(f"""
            SELECT i.InstallmentNo,a.AllocatedAmount
            FROM PaymentAllocation a JOIN LoanInstallment i ON i.InstallmentID=a.InstallmentID
            WHERE a.LoanID={loan} ORDER BY i.InstallmentNo;
        """), "1\t1666.67\n2\t133.33")
        self.assert_rejected(f"CALL RepayLoan({loan},3200.01);", "exceeds outstanding")
        self.sql(f"CALL RepayLoan({loan},3200);")
        self.assertEqual(self.sql(f"SELECT Status FROM Loan WHERE LoanID={loan};"), "CLOSED")

    def wait_for_lock(self, table):
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            waiting = self.sql(f"""
                SELECT COUNT(*)
                FROM performance_schema.data_lock_waits w
                JOIN performance_schema.data_locks l
                  ON l.ENGINE=w.ENGINE
                 AND l.ENGINE_LOCK_ID=w.REQUESTING_ENGINE_LOCK_ID
                WHERE l.OBJECT_SCHEMA='{self.database}' AND l.OBJECT_NAME='{table}';
            """)
            if int(waiting):
                return
            time.sleep(0.1)
        self.fail(f"No repayment reached the expected {table} lock wait")

    def test_concurrent_partial_repayments_cannot_overpay(self):
        loan = self.new_loan()
        before = Decimal(self.sql("SELECT Balance FROM Account WHERE AccountNo=1001;"))
        repay = f"""
            SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;
            CALL RepayLoan({loan},3000);
        """

        with ThreadPoolExecutor(max_workers=2) as workers:
            with subprocess.Popen(
                self.client(), stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                text=True, encoding="utf-8",
            ) as blocker:
                try:
                    blocker.stdin.write(
                        "START TRANSACTION; SELECT AccountNo FROM Account "
                        "WHERE AccountNo=1001 FOR UPDATE;\n"
                    )
                    blocker.stdin.flush()
                    self.assertEqual(blocker.stdout.readline().strip(), "1001")
                    first = workers.submit(self.run_sql, repay)
                    self.wait_for_lock("Account")
                    second = workers.submit(self.run_sql, repay)
                    self.wait_for_lock("Loan")
                finally:
                    blocker.stdin.close()
                    blocker.wait(timeout=10)
            first_result, second_result = first.result(), second.result()

        self.assertEqual(first_result.returncode, 0, first_result.stderr)
        self.assertNotEqual(second_result.returncode, 0, "Both repayments succeeded")
        self.assertIn("exceeds outstanding", second_result.stderr)
        self.assertEqual(self.sql(f"""
            SELECT COUNT(*),SUM(Amount),
                   (SELECT SUM(AllocatedAmount) FROM PaymentAllocation WHERE LoanID={loan})
            FROM Repayment WHERE LoanID={loan};
        """), "1\t3000.00\t3000.00")
        self.assertEqual(Decimal(self.sql("SELECT Balance FROM Account WHERE AccountNo=1001;")),
                         before - Decimal("3000"))


if __name__ == "__main__":
    unittest.main()
