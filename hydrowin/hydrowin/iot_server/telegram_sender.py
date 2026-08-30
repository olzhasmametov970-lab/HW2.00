import os

import requests

BOT_TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN", "")
CHAT_ID = os.environ.get("TELEGRAM_CHAT_ID", "")


def send_photo(path):
    if not BOT_TOKEN or not CHAT_ID:
        raise RuntimeError("Задайте TELEGRAM_BOT_TOKEN и TELEGRAM_CHAT_ID в окружении")
    url = f"https://api.telegram.org/bot{BOT_TOKEN}/sendPhoto"

    with open(path, "rb") as photo:
        requests.post(
            url,
            data={"chat_id": CHAT_ID},
            files={"photo": photo}
        )
