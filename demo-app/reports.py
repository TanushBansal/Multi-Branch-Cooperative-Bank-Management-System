"""Direct report queries shared by the demo, SQL checks, and integration tests."""
from pathlib import Path
import json
import re

SOURCE = Path(__file__).resolve().parent.parent / 'database' / '06_reports.sql'
CATALOG = Path(__file__).resolve().parent / 'report_catalog.json'


def split_statements(text):
    """Split SQL while preserving quoted values and ignoring optional comments."""
    statements, current = [], []
    i, quote = 0, None
    while i < len(text):
        char = text[i]
        if quote:
            current.append(char)
            if char == '\\' and i + 1 < len(text):
                i += 1
                current.append(text[i])
            elif char == quote:
                if i + 1 < len(text) and text[i + 1] == quote:
                    i += 1
                    current.append(text[i])
                else:
                    quote = None
        elif char in "'\"`":
            quote = char
            current.append(char)
        elif (text.startswith('--', i) and
              (i + 2 == len(text) or text[i + 2].isspace())) or char == '#':
            end = text.find('\n', i)
            i = end if end != -1 else len(text)
            current.append('\n')
        elif text.startswith('/*', i):
            end = text.find('*/', i + 2)
            if end == -1:
                raise ValueError('Unclosed SQL comment in report queries')
            i = end + 1
            current.append(' ')
        elif char == ';':
            if ''.join(current).strip():
                statements.append(''.join(current).strip())
            current = []
        else:
            current.append(char)
        i += 1
    if quote:
        raise ValueError('Unclosed quoted value in report queries')
    if ''.join(current).strip():
        statements.append(''.join(current).strip())
    return statements


def load_reports(source=SOURCE, catalog=CATALOG):
    metadata = json.loads(Path(catalog).read_text(encoding='utf-8-sig'))
    statements = split_statements(Path(source).read_text(encoding='utf-8-sig'))
    queries = [sql for sql in statements if not re.fullmatch(r'USE\s+`?\w+`?', sql, re.I)]
    if len(queries) != len(metadata):
        raise ValueError(f'Expected {len(metadata)} report queries in {source}; found {len(queries)}')
    result = {}
    for report, sql in zip(metadata, queries):
        if not re.match(r'^(SELECT|WITH)\b', sql, re.I):
            raise ValueError('Report must be a SELECT or WITH query: ' + report['name'])
        name = report['name']
        if name in result or not re.fullmatch(r'[a-z_]+', name):
            raise ValueError('Invalid or duplicate report name: ' + name)
        if not report['columns'] or not report['keys'] or not set(report['keys']) <= set(report['columns']):
            raise ValueError('Invalid columns or keys for report: ' + name)
        result[name] = {'sql': sql, 'columns': report['columns'], 'keys': report['keys']}
    return result


REPORTS = load_reports()


def expand_sql(sql):
    'Use report names as statement-local CTEs in developer SQL checks.'
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
