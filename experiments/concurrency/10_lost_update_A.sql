-- 10_lost_update_A.sql  (SESSION A, scenario 1: lost update)
-- Account 9100000001 starts at 10000.00.
-- Order: run this script in tab A, then IMMEDIATELY run 10_lost_update_B.sql
-- in tab B. B must start within 15 seconds of A.

USE CooperativeBank;
CALL ConcurrencyDemoReset(9100000001);

SELECT AccountNo, Balance AS BalanceBefore
FROM Account WHERE AccountNo = 9100000001;

-- Withdraw 1000.00. After reading the balance this session waits 15 seconds
-- before writing, which gives session B time to run completely.
CALL WithdrawUnsafe(9100000001, 1000.00, 'cdemo-lu-a', 15);
