-- 30_serializable_B.sql  (SESSION B, scenario 3: resolution with an isolation level)
-- Run in a second tab while session A is still waiting.
-- Expected: one of the two sessions fails with a deadlock error (1213) and
-- is rolled back. The other commits. The failed withdrawal would be retried
-- by the application.

USE CooperativeBank;

SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
CALL WithdrawUnsafe(9100000003, 2000.00, 'cdemo-sr-b', 0);
