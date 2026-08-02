import os


VK_CATEGORY_URL = "https://vijaykarnataka.com/news/bidar/articlelist/11182301.cms"
VK_USER_AGENT = os.getenv(
    "BIDAR_SCRAPER_USER_AGENT",
    "BidarCityNewsBot/1.0 (+mailto:beyondmarks.ai@gmail.com)",
)
SERVICE_BUS_QUEUE = os.getenv("BIDAR_SERVICE_BUS_QUEUE", "bidar-vk-articles")
COSMOS_DATABASE = os.getenv("BIDAR_COSMOS_DATABASE", "gdelt_news")
COSMOS_CONTAINER = os.getenv("BIDAR_COSMOS_CONTAINER", "city_news")
CITY_PARTITION = "bidar"
MAX_CATEGORY_ARTICLES = 50
FULL_REFRESH_SECONDS = 6 * 60 * 60

# Used only when the article establishes the district but no more precise
# locality can be verified. Precise localities are always geocoded.
BIDAR_DISTRICT_POINT = (77.5301, 17.9133)
BIDAR_BOUNDS = {
    "minLon": 76.70,
    "minLat": 17.30,
    "maxLon": 78.25,
    "maxLat": 18.55,
}
