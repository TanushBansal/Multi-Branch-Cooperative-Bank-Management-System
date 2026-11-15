-- 20_row_lock_B.sql  (SESSION B, scenario 2: resolution with a row lock)
-- Run in a second tab while session A is still waiting.
-- This call blocks until A commits (about 15 seconds), then reads the
-- updated balance.

USE CooperativeBank;

CALL WithdrawLocked(9100000002, 2000.00, 'cdemo-rl-b', 0);
