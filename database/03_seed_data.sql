
USE CooperativeBank;

INSERT INTO Bank (BankID, BankName) VALUES
    (1, 'Sahyog Cooperative Bank'),
    (2, 'Pragati Cooperative Bank');

INSERT INTO Branch (BranchID, BankID, IFSC, BranchName, Address) VALUES
    (1, 1, 'SAHY0000001', 'Delhi Central', 'Connaught Place, New Delhi'),
    (2, 1, 'SAHY0000002', 'Jaipur Central', 'MI Road, Jaipur'),
    (3, 1, 'SAHY0000003', 'Pune Central', 'Shivajinagar, Pune'),
    (4, 2, 'PRAG0000001', 'Mumbai Central', 'Dadar, Mumbai');

INSERT INTO Employee (EmployeeID, BranchID, EmployeeName, Phone, Email, EmployeeRole) VALUES
    (1, 1, 'Ananya Sharma', '9000000001', 'ananya.sharma@example.com', 'MANAGER'),
    (2, 1, 'Rohit Verma', '9000000002', 'rohit.verma@example.com', 'CLERK'),
    (3, 2, 'Meera Joshi', '9000000003', 'meera.joshi@example.com', 'MANAGER'),
    (4, 2, 'Karan Singh', '9000000004', 'karan.singh@example.com', 'CLERK'),
    (5, 3, 'Priya Desai', '9000000005', 'priya.desai@example.com', 'MANAGER'),
    (6, 3, 'Amit Kulkarni', '9000000006', 'amit.kulkarni@example.com', 'CLERK'),
    (7, 4, 'Nandita Shah', '9000000007', 'nandita.shah@example.com', 'MANAGER'),
    (8, 4, 'Dev Patel', '9000000008', 'dev.patel@example.com', 'CLERK');

INSERT INTO Manager (EmployeeID) VALUES (1), (3), (5), (7);
INSERT INTO Clerk (EmployeeID) VALUES (2), (4), (6), (8);

INSERT INTO Customer (CustomerID, CustomerName, Phone, Email, PAN, Address) VALUES
    (1, 'Aarav Mehta', '9100000001', 'aarav.mehta@example.com', 'ABCDE1001F', 'Karol Bagh, New Delhi'),
    (2, 'Diya Kapoor', '9100000002', 'diya.kapoor@example.com', 'ABCDE1002F', 'Lajpat Nagar, New Delhi'),
    (3, 'Ishaan Rao', '9100000003', 'ishaan.rao@example.com', 'ABCDE1003F', 'Dwarka, New Delhi'),
    (4, 'Kavya Nair', '9100000004', 'kavya.nair@example.com', 'ABCDE1004F', 'Rohini, New Delhi'),
    (5, 'Neha Saini', '9100000005', 'neha.saini@example.com', 'ABCDE1005F', 'Malviya Nagar, Jaipur'),
    (6, 'Rohan Gupta', '9100000006', 'rohan.gupta@example.com', 'ABCDE1006F', 'Vaishali Nagar, Jaipur'),
    (7, 'Sana Khan', '9100000007', 'sana.khan@example.com', 'ABCDE1007F', 'Mansarovar, Jaipur'),
    (8, 'Vivek Patil', '9100000008', 'vivek.patil@example.com', 'ABCDE1008F', 'Kothrud, Pune'),
    (9, 'Mira Shah', '9100000009', 'mira.shah@example.com', 'ABCDE1009F', 'Dadar, Mumbai'),
    (10, 'Arjun Patel', '9100000010', 'arjun.patel@example.com', 'ABCDE1010F', 'Andheri, Mumbai');

INSERT INTO Account (AccountNo, BranchID, AccountType, Balance, Status, OpenedOn) VALUES
    (1001, 1, 'SAVINGS', 23919.73, 'ACTIVE', '2026-01-01'),
    (1002, 1, 'CURRENT', 50250.00, 'ACTIVE', '2026-01-01'),
    (1003, 1, 'FD', 25000.00, 'ACTIVE', '2026-01-01'),
    (1004, 1, 'SAVINGS', 8000.00, 'FROZEN', '2026-01-01'),
    (2001, 2, 'SAVINGS', 11500.00, 'ACTIVE', '2026-01-01'),
    (2002, 2, 'FD', 40000.00, 'ACTIVE', '2026-01-01'),
    (2003, 2, 'CURRENT', 0.00, 'CLOSED', '2026-01-01'),
    (3001, 3, 'CURRENT', 14000.00, 'ACTIVE', '2026-01-01'),
    (3002, 3, 'SAVINGS', 15000.00, 'ACTIVE', '2026-01-01'),
    (3003, 3, 'FD', 10000.00, 'ACTIVE', '2026-01-01'),
    (4001, 4, 'SAVINGS', 20750.00, 'ACTIVE', '2026-01-01'),
    (4002, 4, 'CURRENT', 29500.00, 'ACTIVE', '2026-01-01');

INSERT INTO AccountHolder (CustomerID, AccountNo) VALUES
    (1, 1001), (2, 1002), (3, 1003), (4, 1004),
    (5, 2001), (6, 2002), (7, 2003), (8, 3001),
    (1, 3002), (5, 3002), (8, 3003), (9, 4001), (10, 4002);

INSERT INTO Nominee (AccountNo, NomineeNo, NomineeName, Relationship, DateOfBirth, Phone, Address) VALUES
    (1001, 1, 'Nisha Mehta', 'Spouse', '1998-04-12', '9200000001', 'Karol Bagh, New Delhi'),
    (1001, 2, 'Raj Mehta', 'Father', '1968-08-20', '9200000002', 'Karol Bagh, New Delhi'),
    (1002, 1, 'Arjun Kapoor', 'Brother', '1995-06-15', '9200000003', 'Lajpat Nagar, New Delhi'),
    (1003, 1, 'Anita Rao', 'Mother', '1970-02-10', '9200000004', 'Dwarka, New Delhi'),
    (1004, 1, 'Dev Nair', 'Spouse', '1994-11-08', '9200000005', 'Rohini, New Delhi'),
    (2001, 1, 'Sunita Saini', 'Mother', '1972-03-19', '9200000006', 'Malviya Nagar, Jaipur'),
    (2002, 1, 'Pooja Gupta', 'Spouse', '1997-09-22', '9200000007', 'Vaishali Nagar, Jaipur'),
    (2003, 1, 'Imran Khan', 'Brother', '1996-01-14', '9200000008', 'Mansarovar, Jaipur'),
    (3001, 1, 'Asha Patil', 'Mother', '1969-07-05', '9200000009', 'Kothrud, Pune'),
    (3002, 1, 'Raj Mehta', 'Father', '1968-08-20', '9200000002', 'Karol Bagh, New Delhi'),
    (3003, 1, 'Asha Patil', 'Mother', '1969-07-05', '9200000009', 'Kothrud, Pune'),
    (4001, 1, 'Ravi Shah', 'Father', '1970-04-10', '9200000010', 'Dadar, Mumbai'),
    (4002, 1, 'Rina Patel', 'Spouse', '1997-08-12', '9200000011', 'Andheri, Mumbai');

INSERT INTO SavingsAccount (AccountNo, InterestRate, MinimumBalance) VALUES
    (1001, 4.00, 1000.00), (1004, 4.00, 1000.00),
    (2001, 4.00, 1000.00), (3002, 4.00, 1000.00), (4001, 4.25, 1000.00);

INSERT INTO CurrentAccount (AccountNo, MinimumBalance) VALUES
    (1002, 5000.00), (2003, 0.00), (3001, 5000.00), (4002, 5000.00);

INSERT INTO FixedDeposit (AccountNo, Principal, InterestRate, StartDate, MaturityDate) VALUES
    (1003, 25000.00, 6.50, '2026-01-02', '2027-01-02'),
    (2002, 40000.00, 6.75, '2026-01-02', '2028-01-02'),
    (3003, 10000.00, 6.00, '2026-01-02', '2027-01-02');

INSERT INTO BankTransaction
    (TransactionID, AccountNo, TransactionDate, TransactionType, Amount, Channel, Status, RequestID) VALUES
    (1, 1001, '2026-01-02 09:00:00', 'DEPOSIT', 20000.00, 'BRANCH', 'SUCCESS', 'seed-deposit-1001'),
    (2, 1002, '2026-01-02 09:05:00', 'DEPOSIT', 50000.00, 'BRANCH', 'SUCCESS', 'seed-deposit-1002'),
    (3, 1003, '2026-01-02 09:10:00', 'DEPOSIT', 25000.00, 'BRANCH', 'SUCCESS', 'seed-fd-1003'),
    (4, 1004, '2026-01-02 09:15:00', 'DEPOSIT', 8000.00, 'BRANCH', 'SUCCESS', 'seed-deposit-1004'),
    (5, 2001, '2026-01-02 09:20:00', 'DEPOSIT', 10000.00, 'BRANCH', 'SUCCESS', 'seed-deposit-2001'),
    (6, 2002, '2026-01-02 09:25:00', 'DEPOSIT', 40000.00, 'BRANCH', 'SUCCESS', 'seed-fd-2002'),
    (7, 2003, '2026-01-02 09:30:00', 'DEPOSIT', 10000.00, 'BRANCH', 'SUCCESS', 'seed-deposit-2003'),
    (8, 3001, '2026-01-02 09:35:00', 'DEPOSIT', 5000.00, 'BRANCH', 'SUCCESS', 'seed-deposit-3001'),
    (9, 3002, '2026-01-02 09:40:00', 'DEPOSIT', 15000.00, 'BRANCH', 'SUCCESS', 'seed-deposit-3002'),
    (10, 3003, '2026-01-02 09:45:00', 'DEPOSIT', 10000.00, 'BRANCH', 'SUCCESS', 'seed-fd-3003'),
    (11, 3001, '2026-05-01 10:00:00', 'LOAN_DISBURSEMENT', 9000.00, 'BRANCH', 'SUCCESS', 'seed-disbursement-4'),
    (12, 2001, '2026-07-01 10:00:00', 'LOAN_DISBURSEMENT', 6000.00, 'BRANCH', 'SUCCESS', 'seed-disbursement-2'),
    (13, 1001, '2026-09-01 10:00:00', 'LOAN_DISBURSEMENT', 12000.00, 'BRANCH', 'SUCCESS', 'seed-disbursement-1'),
    (14, NULL, '2026-09-05 11:00:00', 'TRANSFER', 1500.00, 'ONLINE', 'SUCCESS', 'seed-transfer-inter-1'),
    (15, NULL, '2026-09-06 11:00:00', 'TRANSFER', 500.00, 'ONLINE', 'SUCCESS', 'seed-transfer-inter-2'),
    (16, NULL, '2026-09-07 11:00:00', 'TRANSFER', 250.00, 'ONLINE', 'SUCCESS', 'seed-transfer-intra'),
    (17, 1001, '2026-09-08 12:00:00', 'WITHDRAWAL', 1000.00, 'ATM', 'SUCCESS', 'seed-withdrawal-1001'),
    (18, 1001, '2026-10-01 10:00:00', 'LOAN_REPAYMENT', 3000.00, 'ONLINE', 'SUCCESS', 'seed-repayment-1'),
    (19, 2001, '2026-10-01 11:00:00', 'LOAN_REPAYMENT', 6000.00, 'BRANCH', 'SUCCESS', 'seed-repayment-2'),
    (20, 1001, '2026-11-01 10:00:00', 'LOAN_REPAYMENT', 2080.27, 'ONLINE', 'SUCCESS', 'seed-repayment-3'),
    (21, 2003, '2026-07-01 12:00:00', 'WITHDRAWAL', 10000.00, 'BRANCH', 'SUCCESS', 'seed-close-2003'),
    (22, 1004, '2026-11-14 10:00:00', 'WITHDRAWAL', 20000.00, 'ATM', 'FAILED', 'seed-failed-withdrawal'),
    (23, NULL, '2026-11-15 09:00:00', 'TRANSFER', 750.00, 'ONLINE', 'PENDING', 'seed-pending-transfer'),
    (24, NULL, '2026-11-14 11:00:00', 'TRANSFER', 999999.00, 'ONLINE', 'FAILED', 'seed-failed-transfer'),
    (25, 4001, '2026-01-02 10:00:00', 'DEPOSIT', 20000.00, 'BRANCH', 'SUCCESS', 'seed-deposit-4001'),
    (26, 4002, '2026-01-02 10:05:00', 'DEPOSIT', 30000.00, 'BRANCH', 'SUCCESS', 'seed-deposit-4002'),
    (27, NULL, '2026-11-12 10:00:00', 'TRANSFER', 750.00, 'ONLINE', 'SUCCESS', 'seed-transfer-bank-1'),
    (28, NULL, '2026-11-13 10:00:00', 'TRANSFER', 500.00, 'ONLINE', 'SUCCESS', 'seed-transfer-bank-2'),
    (29, NULL, '2026-11-15 10:00:00', 'TRANSFER', 200.00, 'ONLINE', 'PENDING', 'seed-pending-bank-transfer'),
    (30, NULL, '2026-11-14 12:00:00', 'TRANSFER', 999999.00, 'ONLINE', 'FAILED', 'seed-failed-bank-transfer');

INSERT INTO TransferDetails (TransactionID, FromAccountNo, ToAccountNo) VALUES
    (14, 1001, 2001), (15, 2001, 1002), (16, 1002, 1001),
    (23, 3002, 2001), (24, 1001, 2001),
    (27, 1001, 4001), (28, 4002, 2001),
    (29, 4001, 1002), (30, 1001, 4002);

INSERT INTO LoanApplication
    (ApplicationID, CustomerID, BranchID, ApplicationDate, LoanType,
     RequestedAmount, Purpose, Status, ReviewedBy, DecisionDate) VALUES
    (1, 1, 1, '2026-08-25', 'Personal', 12000.00, 'Home repairs', 'PENDING', NULL, NULL),
    (2, 5, 2, '2026-06-20', 'Education', 6000.00, 'Course fees', 'PENDING', NULL, NULL),
    (3, 1, 3, '2026-11-01', 'Business', 30000.00, 'Equipment purchase', 'PENDING', NULL, NULL),
    (4, 8, 3, '2026-04-20', 'Business', 9000.00, 'Working capital', 'PENDING', NULL, NULL),
    (5, 4, 1, '2026-10-10', 'Personal', 20000.00, 'Travel expenses', 'REJECTED', 1, '2026-10-12 10:00:00'),
    (6, 6, 2, '2026-11-10', 'Personal', 15000.00, 'Medical expenses', 'PENDING', NULL, NULL);

INSERT INTO Guarantor (GuarantorID, GuarantorName, Phone, PAN, Address) VALUES
    (1, 'Suresh Mehta', '9300000001', 'FGHIJ2001K', 'Pitampura, New Delhi'),
    (2, 'Manish Saini', '9300000002', 'FGHIJ2002K', 'Civil Lines, Jaipur'),
    (3, 'Leena Shah', '9300000003', 'FGHIJ2003K', 'Baner, Pune'),
    (4, 'Mahesh Patil', '9300000004', 'FGHIJ2004K', 'Kothrud, Pune');

INSERT INTO ApplicationGuarantor (ApplicationID, GuarantorID) VALUES
    (1, 1), (1, 2), (2, 2), (3, 3), (4, 4), (4, 1), (5, 1), (6, 2);

UPDATE LoanApplication SET Status='APPROVED', ReviewedBy=1, DecisionDate='2026-08-28 10:00:00' WHERE ApplicationID=1;
UPDATE LoanApplication SET Status='APPROVED', ReviewedBy=3, DecisionDate='2026-06-25 10:00:00' WHERE ApplicationID=2;
UPDATE LoanApplication SET Status='APPROVED', ReviewedBy=5, DecisionDate='2026-11-05 10:00:00' WHERE ApplicationID=3;
UPDATE LoanApplication SET Status='APPROVED', ReviewedBy=5, DecisionDate='2026-04-25 10:00:00' WHERE ApplicationID=4;

INSERT INTO Loan
    (LoanID, ApplicationID, PayoutAccountNo, SanctionDate, SanctionAmount,
     InterestRate, TenureMonths, Status, DisbursementTransactionID,
     DisbursementTransactionType, DisbursementTransactionStatus) VALUES
    (1, 1, 1001, '2026-09-01', 12000.00, 12.00, 3, 'ACTIVE', 13, 'LOAN_DISBURSEMENT', 'SUCCESS'),
    (2, 2, 2001, '2026-07-01', 6000.00, 0.00, 3, 'CLOSED', 12, 'LOAN_DISBURSEMENT', 'SUCCESS'),
    (3, 3, 3002, '2026-11-06', 30000.00, 9.00, 6, 'SANCTIONED', NULL, NULL, NULL),
    (4, 4, 3001, '2026-05-01', 9000.00, 12.00, 3, 'DEFAULTED', 11, 'LOAN_DISBURSEMENT', 'SUCCESS');

INSERT INTO LoanInstallment
    (InstallmentID, LoanID, InstallmentNo, DueDate, PrincipalDue, InterestDue) VALUES
    (1, 1, 1, '2026-10-01', 3960.27, 120.00),
    (2, 1, 2, '2026-11-01', 3999.87, 80.40),
    (3, 1, 3, '2026-12-01', 4039.86, 40.40),
    (4, 2, 1, '2026-08-01', 2000.00, 0.00),
    (5, 2, 2, '2026-09-01', 2000.00, 0.00),
    (6, 2, 3, '2026-10-01', 2000.00, 0.00),
    (7, 4, 1, '2026-06-01', 2970.20, 90.00),
    (8, 4, 2, '2026-07-01', 2999.90, 60.30),
    (9, 4, 3, '2026-08-01', 3029.90, 30.30);

INSERT INTO Repayment (PaymentID, LoanID, TransactionID, PaidAt, Amount) VALUES
    (1, 1, 18, '2026-10-01 10:00:00', 3000.00),
    (2, 2, 19, '2026-10-01 11:00:00', 6000.00),
    (3, 1, 20, '2026-11-01 10:00:00', 2080.27);

INSERT INTO PaymentAllocation (PaymentID, InstallmentID, LoanID, AllocatedAmount) VALUES
    (1, 1, 1, 3000.00),
    (2, 4, 2, 2000.00), (2, 5, 2, 2000.00), (2, 6, 2, 2000.00),
    (3, 1, 1, 1080.27), (3, 2, 1, 1000.00);
