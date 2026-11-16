
USE CooperativeBank;
CALL ConcurrencyDemoReset(9100000001);

SELECT AccountNo, Balance AS BalanceBefore
FROM Account WHERE AccountNo = 9100000001;


CALL WithdrawUnsafe(9100000001, 1000.00, 'cdemo-lu-a', 15);
