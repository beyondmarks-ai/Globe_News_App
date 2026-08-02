import os
import unittest
from unittest.mock import Mock, patch

from bidar_news.ai import create_embedding
from bidar_news.extractor import ExtractedArticle, download_html


def article():
    return ExtractedArticle(
        sourceArticleId="1",
        canonicalUrl="https://vijaykarnataka.com/x/articleshow/1.cms",
        headline="????? ????????",
        articleBody="????",
        description="??????",
        imageUrl=None,
        author=None,
        datePublished=None,
        dateModified=None,
        category="Bidar",
        language="kn-IN",
        contentHash="hash",
    )


class AiAndHttpTest(unittest.TestCase):
    @patch("bidar_news.ai.requests.post")
    def test_embedding_parsing(self, post):
        response = Mock()
        response.raise_for_status = Mock()
        response.json.return_value = {"data": [{"embedding": [0.25, "0.5"]}]}
        post.return_value = response
        with patch.dict(
            os.environ,
            {
                "AZURE_OPENAI_ENDPOINT": "https://example.openai.azure.com",
                "AZURE_OPENAI_KEY": "secret",
            },
        ):
            vector = create_embedding(
                article(), {"headlineEnglish": "English headline"}
            )
        self.assertEqual(vector, [0.25, 0.5])
        self.assertEqual(post.call_args.kwargs["json"]["model"], "gdelt-embedding")

    @patch("bidar_news.extractor.requests.get")
    def test_vijaya_response_is_forced_to_utf8(self, get):
        response = Mock(status_code=200, encoding="ISO-8859-1")
        get.return_value = response
        returned = download_html(article().canonicalUrl)
        self.assertIs(returned, response)
        self.assertEqual(response.encoding, "utf-8")


if __name__ == "__main__":
    unittest.main()
