

USE CooperativeBank;
CALL ConcurrencyDemoReset(9100000003);

SELECT AccountNo, Balance AS BalanceBefore
FROM Account WHERE AccountNo = 9100000003;

-- Applies to the next transaction only, then reverts to the default level.
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
CALL WithdrawUnsafe(9100000003, 1000.00, 'cdemo-sr-a', 15);
