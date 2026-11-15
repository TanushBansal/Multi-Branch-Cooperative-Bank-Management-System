-- 20_row_lock_A.sql  (SESSION A, scenario 2: resolution with a row lock)
-- Account 9100000002 starts at 10000.00.
-- Order: run this script in tab A, then IMMEDIATELY run 20_row_lock_B.sql
-- in tab B (within 15 seconds).

USE CooperativeBank;
CALL ConcurrencyDemoReset(9100000002);

SELECT AccountNo, Balance AS BalanceBefore
FROM Account WHERE AccountNo = 9100000002;

-- Same logic as scenario 1, but the read uses FOR UPDATE.
CALL WithdrawLocked(9100000002, 1000.00, 'cdemo-rl-a', 15);
