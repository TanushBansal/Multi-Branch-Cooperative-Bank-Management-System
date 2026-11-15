param(
    [string]$RepoRoot = (Get-Location).Path,
    [string]$MySqlUser = 'root',
    [switch]$UseExistingCredentials
)
$ErrorActionPreference = 'Stop'
$dbDir = Join-Path $RepoRoot 'database'
$fileNames = @(
    '01_schema.sql', '02_account_opening.sql', '02_constraints_triggers.sql',
    '02_loan_dates.sql', '03_seed_data.sql', '04_transactions.sql'
)
foreach ($name in ($fileNames + '07_indexes.sql')) {
    if (-not (Test-Path -LiteralPath (Join-Path $dbDir $name) -PathType Leaf)) {
        throw "Missing $name in $dbDir. Pass the repository root with -RepoRoot."
    }
}
Get-Command mysql -ErrorAction Stop | Out-Null
$scratch = 'CooperativeBank_perf_' + [guid]::NewGuid().ToString('N').Substring(0,8)
$oldPassword = $env:MYSQL_PWD
$oldEncoding = $OutputEncoding

function Invoke-MySql([string]$sql) {
    $result = $sql | mysql --host=127.0.0.1 "--user=$mysqlUser" `
        --default-character-set=utf8mb4 --batch --raw --skip-column-names
    if ($LASTEXITCODE -ne 0) { throw "MySQL exited with code $LASTEXITCODE" }
    $result
}

function Measure-Plan([string]$label, [string]$query) {
    $explain = "USE $scratch; EXPLAIN ANALYZE $query"
    $null = Invoke-MySql $explain  # Warm-up run

    $samples = foreach ($run in 1..5) {
        $plan = (Invoke-MySql $explain) -join "`n"
        $timing = [regex]::Match($plan, 'actual time=[0-9.]+\.\.([0-9.]+)')
        if (-not $timing.Success) { throw "No execution timing found for $label" }
        [double]::Parse($timing.Groups[1].Value, [cultureinfo]::InvariantCulture)
    }

    $median = ($samples | Sort-Object)[2]
    Write-Output "`n$label"
    Write-Output "Samples (ms): $($samples -join ', ')"
    Write-Output "Median (ms): $median"
    Write-Output $plan
}

try {
    if (-not $UseExistingCredentials) {
        $securePassword = Read-Host "MySQL password for $MySqlUser" -AsSecureString
        $credential = [pscredential]::new($MySqlUser, $securePassword)
        $env:MYSQL_PWD = $credential.GetNetworkCredential().Password
    }
    $OutputEncoding = [System.Text.UTF8Encoding]::new($false)

    # 1. Build the scratch database in schema dependency order.
    Write-Output "Scratch database: $scratch"
    Invoke-MySql "CREATE DATABASE $scratch;"
    foreach ($name in $fileNames) {
        Write-Output "Loading $name"
        $sql = Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $dbDir $name)
        $sql = $sql -replace 'CREATE DATABASE IF NOT EXISTS CooperativeBank\s*;', ''
        $sql = $sql -replace 'USE CooperativeBank\s*;', ''
        Invoke-MySql "USE $scratch;`n$sql"
    }

    # 2. Generate 5,000 accounts with 60 matching deposits each.
    Invoke-MySql @"
USE $scratch;
SET SESSION cte_max_recursion_depth = 6000;

CREATE TEMPORARY TABLE bench_numbers (n INT PRIMARY KEY);
INSERT INTO bench_numbers
WITH RECURSIVE seq AS (
    SELECT 0 AS n
    UNION ALL
    SELECT n + 1 FROM seq WHERE n < 4999
)
SELECT n FROM seq;

INSERT INTO Account (AccountNo, BranchID, AccountType, Balance, OpenedOn)
SELECT 100000 + n, 1 + MOD(n, 3), 'SAVINGS', 60 * (1 + MOD(n, 99)), '2024-01-01'
FROM bench_numbers;

INSERT INTO SavingsAccount (AccountNo, InterestRate)
SELECT 100000 + n, 3 FROM bench_numbers;

INSERT INTO AccountHolder (CustomerID, AccountNo)
SELECT 1 + MOD(n, 8), 100000 + n FROM bench_numbers;

INSERT INTO BankTransaction
    (AccountNo, TransactionDate, TransactionType, Amount, Channel, Status, RequestID)
WITH RECURSIVE offsets AS (
    SELECT 0 AS n
    UNION ALL
    SELECT n + 1 FROM offsets WHERE n < 59
)
SELECT 100000 + a.n,
       DATE_ADD('2024-01-01', INTERVAL MOD(a.n * 17 + d.n * 73, 730) DAY),
       'DEPOSIT', 1 + MOD(a.n, 99), 'SYSTEM', 'SUCCESS',
       CONCAT('bench-', a.n, '-', d.n)
FROM bench_numbers a CROSS JOIN offsets d;

SELECT CONCAT('Total transactions: ', COUNT(*)) FROM BankTransaction;
ANALYZE TABLE BankTransaction;
"@

    # 3. Measure both queries before adding the indexes.
    $dateRange = @'
SELECT SUM(Amount) FROM BankTransaction
WHERE TransactionDate >= '2024-06-01' AND TransactionDate < '2024-06-03';
'@

    $accountRange = @'
SELECT SUM(Amount) FROM BankTransaction
WHERE AccountNo = 100100
  AND TransactionDate >= '2024-06-01' AND TransactionDate < '2024-07-01';
'@

    Measure-Plan 'Date range BEFORE' $dateRange
    Measure-Plan 'Account + date range BEFORE' $accountRange

    # 4. Apply 07_indexes.sql to the scratch database.
    $indexes = Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $dbDir '07_indexes.sql')
    $indexes = $indexes -replace 'USE CooperativeBank\s*;', ''
    Invoke-MySql "USE $scratch;`n$indexes`nANALYZE TABLE BankTransaction;"

    # 5. Rerun the same two queries.
    Measure-Plan 'Date range AFTER' $dateRange
    Measure-Plan 'Account + date range AFTER' $accountRange
    Write-Output "Finished. Scratch database: $scratch"
}
finally {
    $env:MYSQL_PWD = $oldPassword
    $OutputEncoding = $oldEncoding
}
