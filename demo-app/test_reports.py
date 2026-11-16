from pathlib import Path
import re
import tempfile
import unittest

import reports


class ReportLoaderTests(unittest.TestCase):
    def load_text(self, text):
        with tempfile.TemporaryDirectory(prefix='cb-report-loader-') as folder:
            source = Path(folder) / 'reports.sql'
            source.write_bytes(text.encode('utf-8'))
            return reports.load_reports(source)

    def test_comment_stripped_copy_has_identical_queries_and_metadata(self):
        original = reports.SOURCE.read_text(encoding='utf-8-sig')
        stripped = re.sub(r'^\s*--[^\n]*', '', original, flags=re.M)
        self.assertEqual(self.load_text(stripped), reports.REPORTS)

    def test_windows_line_endings_and_extra_comments(self):
        original = reports.SOURCE.read_text(encoding='utf-8-sig')
        self.assertEqual(self.load_text(('/* optional; comment */\n' + original).replace('\n', '\r\n')),
                         reports.REPORTS)

    def test_statement_splitter_preserves_quoted_semicolons_and_comment_markers(self):
        self.assertEqual(reports.split_statements("SELECT 'a;--b', 'it''s', `semi;colon`; -- skip;\nSELECT 2;"),
                         ["SELECT 'a;--b', 'it''s', `semi;colon`", 'SELECT 2'])

    def test_incomplete_sql_reports_actual_query_count(self):
        with self.assertRaisesRegex(ValueError, 'Expected 10 report queries.*found 1'):
            self.load_text('USE CooperativeBank; SELECT 1;')

    def test_invalid_statement_is_not_accepted_as_a_report(self):
        original = reports.SOURCE.read_text(encoding='utf-8-sig')
        invalid = original.replace('select t.TransactionID, t.Status, t.RequestID',
                                   'DELETE t.TransactionID, t.Status, t.RequestID', 1)
        with self.assertRaisesRegex(ValueError, 'SELECT or WITH'):
            self.load_text(invalid)
