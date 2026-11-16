"""Direct report queries shared by the demo, SQL checks, and integration tests."""
from pathlib import Path
import re

SOURCE = Path(__file__).resolve().parent.parent / 'database' / '06_reports.sql'
HEADER = re.compile(
    r'^-- report: (\w+)\n-- columns: ([^\n]+)\n-- keys: ([^\n]+)\n', re.M
)


def load_reports():
    text = SOURCE.read_text(encoding='utf-8-sig')
    headers = list(HEADER.finditer(text))
    result = {}
    for i, header in enumerate(headers):
        end = headers[i + 1].start() if i + 1 < len(headers) else len(text)
        name, columns, keys = header.groups()
        result[name] = {
            'sql': text[header.end():end].strip().removesuffix(';'),
            'columns': columns.split(', '),
            'keys': keys.split(', '),
        }
    if len(result) != 10:
        raise ValueError('Expected ten report queries in ' + str(SOURCE))
    return result


REPORTS = load_reports()


def expand_sql(sql):
    """Use report names as statement-local CTEs in developer SQL checks.

    Only the fixed report catalog is expanded. This never creates database objects
    and is not a parser for arbitrary SQL supplied by browser users.
    """
    pattern = r'\b(?:FROM|JOIN)\s+(' + '|'.join(REPORTS) + r')\b'
    if not re.search(pattern, sql, re.I):
        return sql
    statements = []
    for statement in sql.split(';'):
        names = list(dict.fromkeys(re.findall(pattern, statement, re.I)))
        if names:
            definitions = ',\n'.join(
                name + ' AS (\n' + REPORTS[name.lower()]['sql'] + '\n)'
                for name in names
            )
            existing_with = re.match(r'^((?:\s|--[^\n]*(?:\n|$))*)WITH\b', statement, re.I)
            if existing_with:
                statement = 'WITH ' + definitions + ',\n' + statement[existing_with.end():]
            else:
                statement = 'WITH ' + definitions + '\n' + statement
        statements.append(statement)
    return ';'.join(statements)


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description='Print a report query for the MySQL CLI.')
    parser.add_argument('name', choices=list(REPORTS))
    args = parser.parse_args()
    print(REPORTS[args.name]['sql'] + ';')
