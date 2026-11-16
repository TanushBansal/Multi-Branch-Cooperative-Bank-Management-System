"""Validate demo data in a disposable database, using the real schema/triggers.

Run: python -m unittest discover -s tests -p test_seed_data.py -v
Uses the same MYSQL_TEST_CLIENT/HOST/PORT/USER and MYSQL_PWD settings as
test_transactions.py. CooperativeBank is never modified by these tests.
"""

from decimal import Decimal, ROUND_HALF_UP
from concurrent.futures import ThreadPoolExecutor
import os
import sys
from pathlib import Path
import subprocess
import unittest
import uuid


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'demo-app'))
from reports import expand_sql



class SeedDataTest(unittest.TestCase):
    @classmethod
    def run_sql(cls, sql, database=True):
        sql = expand_sql(sql)
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
        # Load the seed fixture. test_loans.py installs and tests the loan procedures separately.
        for path in sorted((ROOT / "database").glob("0[1-7]_*.sql")):
            if path.name not in ("05_loans.sql", "06_reports.sql"):
                cls.execute(cls.load_file(path.name))

    @classmethod
    def drop_database(cls):
        suffix = cls.database.removeprefix("cb_seed_test_")
        if len(suffix) != 32 or any(c not in "0123456789abcdef" for c in suffix):
            raise AssertionError("Unexpected test database name")
        cls.execute("DROP DATABASE " + cls.database, database=False)

    def assert_no_rows(self, sql):
        self.assertEqual(self.execute(sql), "")

    def test_all_tables_populated(self):
        tables = self.execute("SELECT TABLE_NAME FROM information_schema.TABLES "
                              "WHERE TABLE_SCHEMA=DATABASE() AND TABLE_TYPE='BASE TABLE'").splitlines()
        self.assertEqual(len(tables), 21)
        for table in tables:
            with self.subTest(table=table):
                self.assertGreater(int(self.execute(f"SELECT COUNT(*) FROM `{table}`")), 0)

    def test_multi_bank_sample_data_and_transfer_scopes(self):
        self.assertEqual(self.execute('SELECT COUNT(*) FROM Bank'), '2')
        self.assertEqual(self.execute('SELECT COUNT(*) FROM Branch WHERE BankID=2'), '1')
        self.assertEqual(self.execute("SELECT TransactionID,SourceBankID,DestinationBankID,TransferScope "
                                      "FROM transaction_history WHERE TransactionID IN (14,16,27,28) "
                                      "ORDER BY TransactionID"),
                         '14\t1\t1\tINTER_BRANCH\n16\t1\t1\tINTRA_BRANCH\n'
                         '27\t1\t2\tINTER_BANK\n28\t2\t1\tINTER_BANK')
        self.assertEqual(self.execute("SELECT Status FROM transaction_history WHERE "
                                      "TransferScope='INTER_BANK' ORDER BY TransactionID"),
                         'SUCCESS\nSUCCESS\nPENDING\nFAILED')

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
            SELECT m.EmployeeID FROM Manager m JOIN Employee e USING(EmployeeID)
                WHERE e.EmployeeRole IS NULL OR e.EmployeeRole<>'MANAGER' OR m.EmployeeRole<>'MANAGER';
            SELECT c.EmployeeID FROM Clerk c JOIN Employee e USING(EmployeeID)
                WHERE e.EmployeeRole IS NULL OR e.EmployeeRole<>'CLERK' OR c.EmployeeRole<>'CLERK';
        """)
        self.assertEqual(self.execute("SELECT COUNT(*) FROM AccountHolder WHERE AccountNo=3002"), "2")
        self.assertEqual(self.execute("SELECT COUNT(*) FROM Nominee WHERE AccountNo=1001"), "2")

    def employee(self, role=None):
        value = 'NULL' if role is None else "'" + role + "'"
        return int(self.execute("INSERT INTO Employee (BranchID,EmployeeName,EmployeeRole) "
                                f"VALUES (1,'Role test',{value}); SELECT LAST_INSERT_ID();"))

    def reject_role_change(self, sql, message):
        result = self.run_sql(sql)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(message, result.stderr)

    def test_employee_partial_specialization_and_defaults(self):
        employee = self.employee()
        self.assertEqual(self.execute(f"SELECT EmployeeRole IS NULL FROM Employee WHERE EmployeeID={employee}"), "1")
        for table in ('Manager', 'Clerk'):
            self.reject_role_change(f"INSERT INTO {table} (EmployeeID) VALUES ({employee})",
                                    'foreign key constraint fails')
        for table, role in (('Manager', 'MANAGER'), ('Clerk', 'CLERK')):
            employee = self.employee(role)
            self.execute(f"INSERT INTO {table} (EmployeeID) VALUES ({employee})")
            self.assertEqual(self.execute(f"SELECT EmployeeRole FROM {table} WHERE EmployeeID={employee}"), role)

    def test_employee_role_mismatched_inserts_and_updates(self):
        for table, role, opposite in (('Manager','MANAGER','CLERK'), ('Clerk','CLERK','MANAGER')):
            employee = self.employee(role)
            wrong_employee = self.employee(opposite)
            self.reject_role_change(f"INSERT INTO {table} (EmployeeID) VALUES ({wrong_employee})",
                                    'foreign key constraint fails')
            self.execute(f"INSERT INTO {table} (EmployeeID) VALUES ({employee})")
            self.reject_role_change(f"UPDATE {table} SET EmployeeID={wrong_employee} WHERE EmployeeID={employee}",
                                    'foreign key constraint fails')
            self.reject_role_change(f"UPDATE {table} SET EmployeeRole='{opposite}' WHERE EmployeeID={employee}",
                                    'Check constraint')
            self.reject_role_change(f"UPDATE {table} SET EmployeeRole=NULL WHERE EmployeeID={employee}",
                                    'cannot be null')
            for new_role in ("NULL", "'" + opposite + "'"):
                self.reject_role_change(f"UPDATE Employee SET EmployeeRole={new_role} WHERE EmployeeID={employee}",
                                        'foreign key constraint fails')

    def test_employee_cannot_hold_both_roles_concurrently(self):
        employee = self.employee('MANAGER')
        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(lambda table: self.run_sql(
                f"INSERT INTO {table} (EmployeeID) VALUES ({employee})"), ('Manager','Clerk')))
        self.assertEqual(results[0].returncode, 0, results[0].stderr)
        self.assertNotEqual(results[1].returncode, 0)
        self.assertEqual(self.execute(f"SELECT COUNT(*) FROM Manager WHERE EmployeeID={employee}"), "1")
        self.assertEqual(self.execute(f"SELECT COUNT(*) FROM Clerk WHERE EmployeeID={employee}"), "0")

    def test_employee_role_can_change_after_removing_old_subtype(self):
        employee = self.employee('MANAGER')
        self.execute(f"INSERT INTO Manager (EmployeeID) VALUES ({employee}); "
                     f"DELETE FROM Manager WHERE EmployeeID={employee}; "
                     f"UPDATE Employee SET EmployeeRole='CLERK' WHERE EmployeeID={employee}; "
                     f"INSERT INTO Clerk (EmployeeID) VALUES ({employee});")
        self.assertEqual(self.execute(f"SELECT EmployeeRole FROM Clerk WHERE EmployeeID={employee}"), 'CLERK')

    def test_transfer_details_and_reviewers(self):
        self.assert_no_rows("SELECT * FROM transfer_integrity_violations")
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

    def reject_financial_change(self, sql):
        snapshot = ("SELECT * FROM BankTransaction ORDER BY TransactionID; SELECT * FROM Loan ORDER BY LoanID; "
                    "SELECT * FROM Repayment ORDER BY PaymentID; SELECT * FROM LoanInstallment ORDER BY InstallmentID; "
                    "SELECT * FROM PaymentAllocation ORDER BY PaymentID,InstallmentID; "
                    "SELECT * FROM LoanApplication ORDER BY ApplicationID;")
        before = self.execute(snapshot)
        result = self.run_sql(sql)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertEqual(self.execute(snapshot), before)

    def test_disbursement_link_rejects_wrong_account_amount_type_and_status(self):
        # These are unreferenced transactions, so uniqueness cannot mask a bad FK.
        for kind, status, account, amount in (
            ('DEPOSIT','SUCCESS',3002,30000),
            ('LOAN_DISBURSEMENT','FAILED',3002,30000),
            ('LOAN_DISBURSEMENT','PENDING',3002,30000),
            ('LOAN_DISBURSEMENT','SUCCESS',1002,30000),
            ('LOAN_DISBURSEMENT','SUCCESS',3002,29999),
        ):
            transaction = int(self.execute("INSERT INTO BankTransaction "
                "(AccountNo,TransactionType,Amount,Status,RequestID) "
                f"VALUES ({account},'{kind}',{amount},'{status}','invalid-disbursement-{kind}-{status}-{account}-{amount}'); "
                "SELECT LAST_INSERT_ID();"))
            try:
                self.reject_financial_change("UPDATE Loan SET Status='ACTIVE', "
                    f"DisbursementTransactionID={transaction}, "
                    "DisbursementTransactionType='LOAN_DISBURSEMENT', "
                    "DisbursementTransactionStatus='SUCCESS' WHERE LoanID=3")
            finally:
                self.execute(f"DELETE FROM BankTransaction WHERE TransactionID={transaction}")

    def test_disbursement_null_bypasses_and_undisbursed_states_are_rejected(self):
        for changes in (
            "DisbursementTransactionType=NULL", "DisbursementTransactionStatus=NULL",
            "DisbursementTransactionID=NULL", "DisbursementTransactionType='DEPOSIT'",
            "DisbursementTransactionStatus='FAILED'", "Status='SANCTIONED'",
        ):
            self.reject_financial_change(f"UPDATE Loan SET {changes} WHERE LoanID=1")
        for status in ('ACTIVE','CLOSED','DEFAULTED'):
            self.reject_financial_change(f"UPDATE Loan SET Status='{status}' WHERE LoanID=3")
        for changes in ("DisbursementTransactionType='LOAN_DISBURSEMENT'",
                        "DisbursementTransactionStatus='SUCCESS'"):
            self.reject_financial_change(f"UPDATE Loan SET {changes} WHERE LoanID=3")

    def test_sanctioned_loan_accepts_matching_successful_disbursement(self):
        result = self.execute("""
            START TRANSACTION;
            INSERT INTO BankTransaction (AccountNo,TransactionType,Amount,Status,RequestID)
                VALUES (3002,'LOAN_DISBURSEMENT',30000,'SUCCESS','valid-disbursement-transition');
            UPDATE Loan SET Status='ACTIVE', DisbursementTransactionID=LAST_INSERT_ID(),
                DisbursementTransactionType='LOAN_DISBURSEMENT',
                DisbursementTransactionStatus='SUCCESS' WHERE LoanID=3;
            SELECT Status FROM Loan WHERE LoanID=3;
            ROLLBACK;
        """)
        self.assertEqual(result, 'ACTIVE')
        self.assertEqual(self.execute("SELECT Status FROM Loan WHERE LoanID=3"), 'SANCTIONED')

    def test_repayment_links_reject_mismatches(self):
        for changes in ("Amount=999", "TransactionType='DEPOSIT'", "TransactionStatus='FAILED'",
                        "TransactionType=NULL", "TransactionStatus=NULL"):
            self.reject_financial_change(f"UPDATE Repayment SET {changes} WHERE PaymentID=1")
        for kind, status, amount in (('DEPOSIT','SUCCESS',500), ('LOAN_REPAYMENT','FAILED',500),
                                    ('LOAN_REPAYMENT','PENDING',500), ('LOAN_REPAYMENT','SUCCESS',501)):
            transaction = int(self.execute("INSERT INTO BankTransaction "
                "(AccountNo,TransactionType,Amount,Status,RequestID) "
                f"VALUES (1001,'{kind}',{amount},'{status}','invalid-repayment-{kind}-{status}-{amount}'); "
                "SELECT LAST_INSERT_ID();"))
            try:
                self.reject_financial_change("INSERT INTO Repayment (LoanID,TransactionID,Amount) "
                                             f"VALUES (1,{transaction},500)")
            finally:
                self.execute(f"DELETE FROM BankTransaction WHERE TransactionID={transaction}")

    def test_referenced_financial_transactions_cannot_be_invalidated(self):
        for changes in ("Status='FAILED'", "Status='PENDING'", "TransactionType='DEPOSIT'", "Amount=1", "AccountNo=1002"):
            self.reject_financial_change(f"UPDATE BankTransaction SET {changes} WHERE TransactionID=13")
        for changes in ("Status='FAILED'", "Status='PENDING'", "TransactionType='WITHDRAWAL'", "Amount=1"):
            self.reject_financial_change(f"UPDATE BankTransaction SET {changes} WHERE TransactionID=18")
        self.reject_financial_change("UPDATE Loan SET PayoutAccountNo=1002 WHERE LoanID=1")
        self.reject_financial_change("UPDATE Loan SET SanctionAmount=1 WHERE LoanID=1")

    def guarantor_application(self, guarantors=(), approved=False):
        application = int(self.execute("INSERT INTO LoanApplication "
            "(CustomerID,BranchID,ApplicationDate,LoanType,RequestedAmount) "
            "VALUES (1,1,'2026-11-01','Test',1000); SELECT LAST_INSERT_ID();"))
        for guarantor in guarantors:
            self.execute(f"INSERT INTO ApplicationGuarantor VALUES ({application},{guarantor})")
        if approved:
            self.execute(self.approve_sql(application))
        return application

    @staticmethod
    def approve_sql(application):
        return ("UPDATE LoanApplication SET Status='APPROVED',ReviewedBy=1,"
                f"DecisionDate='2026-11-02' WHERE ApplicationID={application}")

    def test_guarantor_required_for_approval_and_direct_approved_insert(self):
        result = self.run_sql("INSERT INTO LoanApplication "
            "(CustomerID,BranchID,ApplicationDate,LoanType,RequestedAmount,Status,ReviewedBy,DecisionDate) "
            "VALUES (1,1,'2026-11-01','Test',1000,'APPROVED',1,'2026-11-02')")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('guarantor', result.stderr)
        application = self.guarantor_application()
        result = self.run_sql(self.approve_sql(application))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('guarantor', result.stderr)
        self.assertEqual(self.execute(f"SELECT Status FROM LoanApplication WHERE ApplicationID={application}"), 'PENDING')
        self.execute(f"INSERT INTO ApplicationGuarantor VALUES ({application},1)")
        self.execute(self.approve_sql(application))

    def test_guarantor_last_delete_and_move_are_blocked(self):
        application = self.guarantor_application((1,), True)
        target = self.guarantor_application()
        for sql in (f"DELETE FROM ApplicationGuarantor WHERE ApplicationID={application}",
                    f"UPDATE ApplicationGuarantor SET ApplicationID={target} WHERE ApplicationID={application}"):
            result = self.run_sql(sql)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('last guarantor', result.stderr)
        self.assertEqual(self.execute(f"SELECT COUNT(*) FROM ApplicationGuarantor WHERE ApplicationID={application}"), '1')

    def test_guarantor_nonlast_delete_move_and_replacement_are_allowed(self):
        application = self.guarantor_application((1,2), True)
        target = self.guarantor_application()
        self.execute(f"UPDATE ApplicationGuarantor SET ApplicationID={target} WHERE ApplicationID={application} AND GuarantorID=1")
        self.execute(f"INSERT INTO ApplicationGuarantor VALUES ({application},4)")
        self.execute(f"UPDATE ApplicationGuarantor SET GuarantorID=3 WHERE ApplicationID={application} AND GuarantorID=2")
        self.execute(f"DELETE FROM ApplicationGuarantor WHERE ApplicationID={application} AND GuarantorID=4")
        self.assertEqual(self.execute(f"SELECT GuarantorID FROM ApplicationGuarantor WHERE ApplicationID={application}"), '3')

    def test_guarantor_multirow_delete_rolls_back_whole_statement(self):
        application = self.guarantor_application((1,2), True)
        result = self.run_sql(f"DELETE FROM ApplicationGuarantor WHERE ApplicationID={application}")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('last guarantor', result.stderr)
        self.assertEqual(self.execute(f"SELECT COUNT(*) FROM ApplicationGuarantor WHERE ApplicationID={application}"), '2')

    def test_guarantor_pending_application_links_can_be_removed(self):
        application = self.guarantor_application((1,))
        self.execute(f"DELETE FROM ApplicationGuarantor WHERE ApplicationID={application}")
        self.assertEqual(self.execute(f"SELECT COUNT(*) FROM ApplicationGuarantor WHERE ApplicationID={application}"), '0')

    def test_guarantor_concurrent_deletes_preserve_one_link(self):
        application = self.guarantor_application((1,2), True)
        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(lambda guarantor: self.run_sql(
                f"DELETE FROM ApplicationGuarantor WHERE ApplicationID={application} AND GuarantorID={guarantor}"), (1,2)))
        self.assertEqual(sum(result.returncode == 0 for result in results), 1)
        self.assertEqual(self.execute(f"SELECT COUNT(*) FROM ApplicationGuarantor WHERE ApplicationID={application}"), '1')

    def test_guarantor_concurrent_approval_and_delete_remain_consistent(self):
        application = self.guarantor_application((1,))
        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(self.run_sql, (self.approve_sql(application),
                f"DELETE FROM ApplicationGuarantor WHERE ApplicationID={application}")))
        self.assertEqual(sum(result.returncode == 0 for result in results), 1)
        self.assert_no_rows("SELECT a.ApplicationID FROM LoanApplication a WHERE a.Status='APPROVED' "
            "AND NOT EXISTS (SELECT 1 FROM ApplicationGuarantor g WHERE g.ApplicationID=a.ApplicationID)")

    def test_guarantor_designation_must_reference_own_live_link(self):
        application = self.guarantor_application((1,), True)
        result = self.run_sql(f"UPDATE LoanApplication SET ApprovalGuarantorID=4 WHERE ApplicationID={application}")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('foreign key constraint fails', result.stderr)
        self.assertEqual(self.execute(f"SELECT ApprovalGuarantorID FROM LoanApplication WHERE ApplicationID={application}"), '1')

    def test_guarantor_concurrent_reassignments_preserve_one_link(self):
        application = self.guarantor_application((1,2), True)
        targets = (self.guarantor_application(), self.guarantor_application())
        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(lambda pair: self.run_sql(
                f"UPDATE ApplicationGuarantor SET ApplicationID={pair[1]} "
                f"WHERE ApplicationID={application} AND GuarantorID={pair[0]}"), zip((1,2),targets)))
        self.assertEqual(sum(result.returncode == 0 for result in results), 1)
        self.assertEqual(self.execute(f"SELECT COUNT(*) FROM ApplicationGuarantor WHERE ApplicationID={application}"), '1')

    def test_loan_rejects_pending_and_rejected_applications(self):
        for application in (5,6):
            # These seed applications have no loans, so UNIQUE cannot mask a bad FK.
            sql = ("INSERT INTO Loan (ApplicationID,PayoutAccountNo,SanctionDate,SanctionAmount,InterestRate,TenureMonths) "
                   f"VALUES ({application},1001,'2026-11-15',1000,5,3)")
            result = self.run_sql(sql)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('foreign key constraint fails', result.stderr)
            self.reject_financial_change(f"UPDATE Loan SET ApplicationID={application} WHERE LoanID=3")

    def test_loan_application_status_cannot_be_bypassed(self):
        for status in ("'PENDING'", "'REJECTED'", "NULL"):
            self.reject_financial_change(f"UPDATE Loan SET ApplicationStatus={status} WHERE LoanID=3")
        self.assertEqual(self.execute("SELECT DISTINCT ApplicationStatus FROM Loan"), 'APPROVED')

    def test_linked_loan_approval_cannot_be_revoked(self):
        for sql in (
            "UPDATE LoanApplication SET Status='PENDING',ReviewedBy=NULL,DecisionDate=NULL WHERE ApplicationID=3",
            "UPDATE LoanApplication SET Status='REJECTED' WHERE ApplicationID=3",
        ):
            # The decision CHECK is satisfied; the composite loan FK blocks revocation.
            result = self.run_sql(sql)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('foreign key constraint fails', result.stderr)
            self.assertEqual(self.execute("SELECT Status FROM LoanApplication WHERE ApplicationID=3"), 'APPROVED')

    def test_approved_application_accepts_loan_with_default_status(self):
        application = self.guarantor_application((1,), True)
        # Roll back this additional loan so EMI/reporting seed expectations stay unchanged.
        result = self.execute("START TRANSACTION; "
            "INSERT INTO Loan (ApplicationID,PayoutAccountNo,SanctionDate,SanctionAmount,InterestRate,TenureMonths) "
            f"VALUES ({application},1001,'2026-11-15',1000,5,3); "
            f"SELECT ApplicationStatus FROM Loan WHERE ApplicationID={application}; ROLLBACK;")
        self.assertEqual(result, 'APPROVED')

    def test_chronology_application_and_sanction_updates(self):
        for sql in (
            "UPDATE LoanApplication SET DecisionDate='2026-08-01' WHERE ApplicationID=1",
            "UPDATE LoanApplication SET ApplicationDate='2026-09-01' WHERE ApplicationID=1",
            "UPDATE LoanApplication SET DecisionDate='2026-09-02' WHERE ApplicationID=1",
            "UPDATE Loan SET SanctionDate='2026-08-01' WHERE LoanID=1",
            "UPDATE Loan SET SanctionDate='2026-09-02' WHERE LoanID=1",
        ):
            self.reject_financial_change(sql)

    def test_chronology_new_loan_cannot_precede_approval(self):
        application = self.guarantor_application((1,), True)
        self.reject_financial_change("INSERT INTO Loan "
            "(ApplicationID,PayoutAccountNo,SanctionDate,SanctionAmount,InterestRate,TenureMonths) "
            f"VALUES ({application},1001,'2026-11-01',1000,5,3)")

    def test_chronology_disbursement_reassignment_checks_existing_schedule(self):
        for date in ('2026-08-31 10:00:00','2026-10-02 10:00:00'):
            transaction = self.execute("INSERT INTO BankTransaction "
                "(AccountNo,TransactionDate,TransactionType,Amount,Status,RequestID) "
                f"VALUES (1001,'{date}','LOAN_DISBURSEMENT',12000,'SUCCESS','date-{date}'); "
                "SELECT LAST_INSERT_ID();")
            try:
                self.reject_financial_change(f"UPDATE Loan SET DisbursementTransactionID={transaction} WHERE LoanID=1")
            finally:
                self.execute(f"DELETE FROM BankTransaction WHERE TransactionID={transaction}")

    def test_chronology_installment_insert_and_update(self):
        self.reject_financial_change("INSERT INTO LoanInstallment "
            "(LoanID,InstallmentNo,DueDate,PrincipalDue,InterestDue) VALUES (1,99,'2026-09-01',1,0)")
        self.reject_financial_change("UPDATE LoanInstallment SET DueDate='2026-09-01' WHERE InstallmentID=1")

    def test_chronology_repayment_timestamp_and_transaction_date(self):
        self.reject_financial_change("UPDATE Repayment SET PaidAt='2026-09-01 09:59:59' WHERE PaymentID=1")
        transaction = self.execute("INSERT INTO BankTransaction "
            "(AccountNo,TransactionDate,TransactionType,Amount,Status,RequestID) "
            "VALUES (1001,'2026-08-31','LOAN_REPAYMENT',123,'SUCCESS','early-repayment-date'); "
            "SELECT LAST_INSERT_ID();")
        try:
            self.reject_financial_change("INSERT INTO Repayment (LoanID,TransactionID,PaidAt,Amount) "
                f"VALUES (1,{transaction},'2026-10-01',123)")
        finally:
            self.execute(f"DELETE FROM BankTransaction WHERE TransactionID={transaction}")

    def test_chronology_linked_financial_timestamps_are_immutable(self):
        for transaction in (13,18):
            for date in ('2026-01-01','2027-01-01'):
                result = self.run_sql(f"UPDATE BankTransaction SET TransactionDate='{date}' WHERE TransactionID={transaction}")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('timestamps cannot change', result.stderr)

    def test_chronology_funding_cannot_move_after_payment_without_schedule(self):
        self.reject_financial_change("""
            START TRANSACTION;
            INSERT INTO BankTransaction (AccountNo,TransactionDate,TransactionType,Amount,Status,RequestID)
                VALUES (3002,'2026-11-06','LOAN_DISBURSEMENT',30000,'SUCCESS','date-funding');
            UPDATE Loan SET Status='ACTIVE',DisbursementTransactionID=LAST_INSERT_ID(),
                DisbursementTransactionType='LOAN_DISBURSEMENT',DisbursementTransactionStatus='SUCCESS' WHERE LoanID=3;
            INSERT INTO BankTransaction (AccountNo,TransactionDate,TransactionType,Amount,Status,RequestID)
                VALUES (3002,'2026-11-07','LOAN_REPAYMENT',100,'SUCCESS','date-payment');
            INSERT INTO Repayment (LoanID,TransactionID,PaidAt,Amount) VALUES (3,LAST_INSERT_ID(),'2026-11-07',100);
            INSERT INTO BankTransaction (AccountNo,TransactionDate,TransactionType,Amount,Status,RequestID)
                VALUES (3002,'2026-11-08','LOAN_DISBURSEMENT',30000,'SUCCESS','date-late-funding');
            UPDATE Loan SET DisbursementTransactionID=LAST_INSERT_ID() WHERE LoanID=3;
            COMMIT;
        """)

    def test_chronology_equal_day_approval_and_exact_funding_time_are_allowed(self):
        self.execute("""
            START TRANSACTION;
            UPDATE LoanApplication SET DecisionDate='2026-09-01 12:00:00' WHERE ApplicationID=1;
            UPDATE Repayment SET PaidAt='2026-09-01 10:00:00' WHERE PaymentID=1;
            UPDATE LoanInstallment SET DueDate='2026-09-02' WHERE InstallmentID=1;
            ROLLBACK;
        """)

    def test_sanction_cannot_exceed_request_on_insert_or_update(self):
        application = self.guarantor_application((1,), True)
        result = self.run_sql("INSERT INTO Loan "
            "(ApplicationID,PayoutAccountNo,SanctionDate,SanctionAmount,InterestRate,TenureMonths) "
            f"VALUES ({application},1001,'2026-11-15',1000.01,5,3)")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('cannot exceed the requested amount', result.stderr)
        # Loan 3 is undisbursed, so its transaction-amount FK cannot mask the limit.
        self.reject_financial_change("UPDATE Loan SET SanctionAmount=30000.01 WHERE LoanID=3")
        self.reject_financial_change(f"UPDATE Loan SET ApplicationID={application} WHERE LoanID=3")

    def test_requested_amount_cannot_drop_below_existing_sanction(self):
        result = self.run_sql("UPDATE LoanApplication SET RequestedAmount=29999.99 WHERE ApplicationID=3")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('below the existing sanction amount', result.stderr)
        self.assertEqual(self.execute("SELECT RequestedAmount FROM LoanApplication WHERE ApplicationID=3"), '30000.00')

    def test_sanction_and_request_equality_is_allowed(self):
        application = self.guarantor_application((1,), True)
        result = self.execute("START TRANSACTION; INSERT INTO Loan "
            "(ApplicationID,PayoutAccountNo,SanctionDate,SanctionAmount,InterestRate,TenureMonths) "
            f"VALUES ({application},1001,'2026-11-15',1000,5,3); "
            f"UPDATE Loan SET SanctionAmount=950 WHERE ApplicationID={application}; "
            f"UPDATE LoanApplication SET RequestedAmount=950 WHERE ApplicationID={application}; "
            f"SELECT SanctionAmount FROM Loan WHERE ApplicationID={application}; ROLLBACK;")
        self.assertEqual(result, '950.00')

    def test_concurrent_sanction_and_request_reduction_are_consistent(self):
        application = self.guarantor_application((1,), True)
        insert = ("INSERT INTO Loan "
            "(ApplicationID,PayoutAccountNo,SanctionDate,SanctionAmount,InterestRate,TenureMonths) "
            f"VALUES ({application},1001,'2026-11-15',800,5,3)")
        reduce = f"UPDATE LoanApplication SET RequestedAmount=500 WHERE ApplicationID={application}"
        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(self.run_sql, (insert, reduce)))
        self.assertEqual(sum(result.returncode == 0 for result in results), 1)
        self.assert_no_rows("SELECT l.LoanID FROM Loan l JOIN LoanApplication a USING(ApplicationID) "
                            "WHERE l.SanctionAmount>a.RequestedAmount")

    def test_concurrent_sanction_increase_and_request_reduction_are_consistent(self):
        application = self.guarantor_application((1,), True)
        self.execute("INSERT INTO Loan "
            "(ApplicationID,PayoutAccountNo,SanctionDate,SanctionAmount,InterestRate,TenureMonths) "
            f"VALUES ({application},1001,'2026-11-15',500,5,3)")
        increase = f"UPDATE Loan SET SanctionAmount=800 WHERE ApplicationID={application}"
        reduce = f"UPDATE LoanApplication SET RequestedAmount=600 WHERE ApplicationID={application}"
        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(self.run_sql, (increase, reduce)))
        self.assertEqual(sum(result.returncode == 0 for result in results), 1)
        self.assert_no_rows("SELECT l.LoanID FROM Loan l JOIN LoanApplication a USING(ApplicationID) "
                            "WHERE l.SanctionAmount>a.RequestedAmount")

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

    def test_allocation_rejects_cross_loan_inserts(self):
        for payment, installment, loan in ((1,4,1), (1,4,2), (1,3,9999)):
            self.reject_financial_change(
                "INSERT INTO PaymentAllocation (PaymentID,InstallmentID,LoanID,AllocatedAmount) "
                f"VALUES ({payment},{installment},{loan},1)")
        self.reject_financial_change(
            "INSERT INTO PaymentAllocation (PaymentID,InstallmentID,LoanID,AllocatedAmount) VALUES (1,3,NULL,1)")

    def test_allocation_updates_cannot_change_loan_membership(self):
        for changes in ("PaymentID=2", "InstallmentID=4", "LoanID=2", "LoanID=NULL"):
            self.reject_financial_change(
                f"UPDATE PaymentAllocation SET {changes} WHERE PaymentID=1 AND InstallmentID=1")

    def test_allocated_parents_cannot_be_moved_to_another_loan(self):
        self.reject_financial_change("UPDATE Repayment SET LoanID=2 WHERE PaymentID=1")
        # Avoid the existing UNIQUE(LoanID,InstallmentNo), so the new FK is tested.
        self.reject_financial_change("UPDATE LoanInstallment SET LoanID=2,InstallmentNo=99 WHERE InstallmentID=1")

    def test_repayments_and_allocations(self):
        self.assert_no_rows("""
            SELECT r.PaymentID FROM Repayment r JOIN BankTransaction t USING(TransactionID)
            WHERE t.Status<>'SUCCESS' OR t.TransactionType<>'LOAN_REPAYMENT'
               OR t.Amount<>r.Amount OR t.TransactionDate<>r.PaidAt;
            SELECT p.PaymentID FROM PaymentAllocation p
            JOIN Repayment r USING(PaymentID) JOIN LoanInstallment i USING(InstallmentID)
            WHERE r.LoanID<>i.LoanID OR p.LoanID<>r.LoanID OR p.LoanID<>i.LoanID;
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
