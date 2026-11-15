-- 30_serializable_A.sql  (SESSION A, scenario 3: resolution with an isolation level)
-- Account 9100000003 starts at 10000.00. The UNSAFE procedure is used again,
-- but the transaction runs at SERIALIZABLE, so the database itself prevents
-- the lost update.
-- Order: run this script in tab A, then IMMEDIATELY run 30_serializable_B.sql
-- in tab B (within 15 seconds).

USE CooperativeBank;
CALL ConcurrencyDemoReset(9100000003);

SELECT AccountNo, Balance AS BalanceBefore
FROM Account WHERE AccountNo = 9100000003;

-- Applies to the next transaction only, then reverts to the default level.
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
CALL WithdrawUnsafe(9100000003, 1000.00, 'cdemo-sr-a', 15);
