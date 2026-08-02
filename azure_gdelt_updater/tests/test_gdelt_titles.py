import gzip
import json
import unittest

from azure_gdelt_updater.gdelt_titles import article_url_key, load_gdelt_titles, title_for_url


class _Response:
    def __init__(self, status_code, documents=None):
        self.status_code = status_code
        lines = [json.dumps(document) for document in documents or []]
        self.content = gzip.compress("\n".join(lines).encode("utf-8"))

    def raise_for_status(self):
        if self.status_code >= 400:
            raise RuntimeError("request failed")


class _Session:
    def __init__(self):
        self.urls = []

    def get(self, url, timeout):
        self.urls.append(url)
        if "20260802134600" in url:
            return _Response(200, [{"url": "https://Example.com/story/?tracking=yes", "title": "  Real   GDELT headline  "}])
        return _Response(404)


class GdeltTitlesTest(unittest.TestCase):
    def test_url_key_handles_scheme_query_and_trailing_slash(self):
        self.assertEqual(article_url_key("http://EXAMPLE.com:80/story/?x=1"), "example.com/story")

    def test_loads_expected_gal_window_and_matches_gkg_url(self):
        session = _Session()
        titles = load_gdelt_titles("20260802140000", session=session)
        self.assertEqual(len(session.urls), 4)
        self.assertEqual(title_for_url(titles, "http://example.com/story"), "Real GDELT headline")


if __name__ == "__main__":
    unittest.main()
