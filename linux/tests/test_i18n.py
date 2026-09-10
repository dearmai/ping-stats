import unittest

from pingstats.i18n import language


class LanguageTests(unittest.TestCase):
    def test_language_preferences(self):
        cases = [
            ({}, "ko"),
            ({"LANG": "C.UTF-8"}, "ko"),
            ({"LANG": "ko_KR.UTF-8"}, "ko"),
            ({"LANG": "en_US.UTF-8"}, "en"),
            ({"LANG": "en_US.UTF-8", "LC_MESSAGES": "ko_KR.UTF-8"}, "ko"),
            ({"LANG": "ko_KR.UTF-8", "LC_ALL": "en_US.UTF-8"}, "en"),
            ({"LANG": "en_US.UTF-8", "LANGUAGE": "fr:ko:en"}, "ko"),
            ({"LANG": "ko_KR.UTF-8", "PINGSTATS_LANGUAGE": "en"}, "en"),
            ({"LANG": "en_US.UTF-8", "PINGSTATS_LANGUAGE": "ko"}, "ko"),
            ({"LANG": "en_US.UTF-8", "PINGSTATS_LANGUAGE": "invalid"}, "en"),
        ]
        for environ, expected in cases:
            with self.subTest(environ=environ):
                self.assertEqual(language(environ), expected)
