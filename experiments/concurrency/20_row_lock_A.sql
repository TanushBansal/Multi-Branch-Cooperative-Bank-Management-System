
USE CooperativeBank;
CALL ConcurrencyDemoReset(9100000002);

SELECT AccountNo, Balance AS BalanceBefore
FROM Account WHERE AccountNo = 9100000002;

CALL WithdrawLocked(9100000002, 1000.00, 'cdemo-rl-a', 15);
