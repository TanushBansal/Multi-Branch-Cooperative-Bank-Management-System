-- 10_lost_update_B.sql  (SESSION B, scenario 1: lost update)
-- Run in a second tab while session A is still waiting.

USE CooperativeBank;

-- Withdraw 2000.00 with no delay. This completes before A wakes up.
CALL WithdrawUnsafe(9100000001, 2000.00, 'cdemo-lu-b', 0);
