import json
import unittest

from bidar_news.extractor import (
    canonical_article_url,
    discover_articles,
    extract_article,
)


ARTICLE_URL = "https://vijaykarnataka.com/news/bidar/sample/articleshow/123456789.cms"


class ExtractorTest(unittest.TestCase):
    def test_discovery_deduplicates_and_rejects_other_hosts(self):
        html = """
        <a href="/news/bidar/one/articleshow/123456789.cms">one</a>
        <a href="https://vijaykarnataka.com/news/bidar/one/articleshow/123456789.cms?x=1">duplicate</a>
        <a href="https://example.com/articleshow/999999.cms">bad</a>
        """
        results = discover_articles(html)
        self.assertEqual(len(results), 1)
        self.assertEqual(results[0].sourceArticleId, "123456789")
        self.assertNotIn("?", results[0].canonicalUrl)

    def test_json_ld_has_priority(self):
        data = {
            "@context": "https://schema.org",
            "@type": "NewsArticle",
            "url": ARTICLE_URL,
            "headline": "????? ??????",
            "articleBody": "????? ????? ????. " * 20,
            "description": "??????",
            "image": {"url": "https://example.com/image.jpg"},
            "author": {"name": "Reporter"},
            "datePublished": "2026-08-01T09:00:00+05:30",
            "dateModified": "2026-08-01T09:10:00+05:30",
        }
        html = (
            '<html><head><meta property="og:title" content="Wrong">'
            '<script type="application/ld+json">'
            + json.dumps(data, ensure_ascii=False)
            + "</script></head><body></body></html>"
        )
        article = extract_article(html, ARTICLE_URL)
        self.assertEqual(article.headline, "????? ??????")
        self.assertEqual(article.author, "Reporter")
        self.assertEqual(article.language, "kn-IN")
        self.assertEqual(article.imageUrl, "https://example.com/image.jpg")
        self.assertEqual(len(article.contentHash), 64)

    def test_meta_and_selector_fallback(self):
        body = "Fallback article body " * 20
        html = f"""
        <html><head>
          <meta property="og:title" content="Fallback headline">
          <meta name="description" content="Fallback description">
        </head><body><div itemprop="articleBody">{body}</div></body></html>
        """
        article = extract_article(html, ARTICLE_URL)
        self.assertEqual(article.headline, "Fallback headline")
        self.assertIn("Fallback article body", article.articleBody)

    def test_incomplete_article_is_rejected(self):
        with self.assertRaises(ValueError):
            extract_article("<h1>Title</h1><p>short</p>", ARTICLE_URL)

    def test_non_vijaya_url_is_rejected(self):
        self.assertIsNone(
            canonical_article_url("https://example.com/articleshow/123456789.cms")
        )


if __name__ == "__main__":
    unittest.main()
