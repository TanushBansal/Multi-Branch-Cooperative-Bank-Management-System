-- 02_constraints_triggers.sql
-- Additional constraints and triggers layered on top of 01_schema.sql.
-- Requires MySQL 8.0.16 or later.

USE CooperativeBank;

-- ---------------------------------------------------------------
-- A. Format checks on identifying information
-- ---------------------------------------------------------------

ALTER TABLE Customer
    ADD CONSTRAINT chk_customer_pan
    CHECK (REGEXP_LIKE(PAN, '^[A-Z]{5}[0-9]{4}[A-Z]$', 'c'));

ALTER TABLE Guarantor
    ADD CONSTRAINT chk_guarantor_pan
    CHECK (REGEXP_LIKE(PAN, '^[A-Z]{5}[0-9]{4}[A-Z]$', 'c'));

ALTER TABLE Branch
    ADD CONSTRAINT chk_branch_ifsc
    CHECK (REGEXP_LIKE(IFSC, '^[A-Z]{4}0[A-Z0-9]{6}$', 'c'));

-- A loan decision is recorded together or not at all: a pending
-- application has no reviewer and no decision date, a decided one has both.
ALTER TABLE LoanApplication
    ADD CONSTRAINT chk_application_decision
    CHECK (
        (Status = 'PENDING'  AND ReviewedBy IS NULL     AND DecisionDate IS NULL)
        OR
        (Status <> 'PENDING' AND ReviewedBy IS NOT NULL AND DecisionDate IS NOT NULL)
    );

DELIMITER $$

-- ---------------------------------------------------------------
-- B. Employee specialization is disjoint (a manager is never a clerk)
-- ---------------------------------------------------------------

CREATE TRIGGER trg_manager_not_clerk
BEFORE INSERT ON Manager
FOR EACH ROW
BEGIN
    IF EXISTS (SELECT 1 FROM Clerk WHERE EmployeeID = NEW.EmployeeID) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Employee is already a clerk and cannot also be a manager';
    END IF;
END$$

CREATE TRIGGER trg_clerk_not_manager
BEFORE INSERT ON Clerk
FOR EACH ROW
BEGIN
    IF EXISTS (SELECT 1 FROM Manager WHERE EmployeeID = NEW.EmployeeID) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Employee is already a manager and cannot also be a clerk';
    END IF;
END$$

-- ---------------------------------------------------------------
-- C. Account specialization: subtype row must match Account.AccountType,
--    and the type of an existing account can never change
-- ---------------------------------------------------------------

CREATE TRIGGER trg_savings_type_match
BEFORE INSERT ON SavingsAccount
FOR EACH ROW
BEGIN
    IF (SELECT AccountType FROM Account WHERE AccountNo = NEW.AccountNo) <> 'SAVINGS' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Account is not of type SAVINGS';
    END IF;
END$$

CREATE TRIGGER trg_current_type_match
BEFORE INSERT ON CurrentAccount
FOR EACH ROW
BEGIN
    IF (SELECT AccountType FROM Account WHERE AccountNo = NEW.AccountNo) <> 'CURRENT' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Account is not of type CURRENT';
    END IF;
END$$

CREATE TRIGGER trg_fd_type_match
BEFORE INSERT ON FixedDeposit
FOR EACH ROW
BEGIN
    IF (SELECT AccountType FROM Account WHERE AccountNo = NEW.AccountNo) <> 'FD' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Account is not of type FD';
    END IF;
END$$

CREATE TRIGGER trg_account_type_immutable
BEFORE UPDATE ON Account
FOR EACH ROW
BEGIN
    IF NEW.AccountType <> OLD.AccountType THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'AccountType cannot be changed after account creation';
    END IF;
END$$

-- ---------------------------------------------------------------
-- D. A transfer detail row must belong to a TRANSFER transaction
-- ---------------------------------------------------------------

CREATE TRIGGER trg_transferdetails_type
BEFORE INSERT ON TransferDetails
FOR EACH ROW
BEGIN
    IF (SELECT TransactionType FROM BankTransaction
        WHERE TransactionID = NEW.TransactionID) <> 'TRANSFER' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'TransferDetails requires a TRANSFER transaction';
    END IF;
END$$

-- ---------------------------------------------------------------
-- E. The reviewing manager must belong to the branch that received
--    the loan application
-- ---------------------------------------------------------------

CREATE TRIGGER trg_application_reviewer_ins
BEFORE INSERT ON LoanApplication
FOR EACH ROW
BEGIN
    IF NEW.ReviewedBy IS NOT NULL AND
       (SELECT BranchID FROM Employee WHERE EmployeeID = NEW.ReviewedBy) <> NEW.BranchID THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Reviewer must be a manager of the receiving branch';
    END IF;
END$$

CREATE TRIGGER trg_application_reviewer_upd
BEFORE UPDATE ON LoanApplication
FOR EACH ROW
BEGIN
    IF NEW.ReviewedBy IS NOT NULL AND
       (SELECT BranchID FROM Employee WHERE EmployeeID = NEW.ReviewedBy) <> NEW.BranchID THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Reviewer must be a manager of the receiving branch';
    END IF;
END$$

DELIMITER ;