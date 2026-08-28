import requests

BOT_TOKEN = "8765018100:AAEafmzaiLxBFeR6ceAydnQNSPP-bPPxumQ"
CHAT_ID = "294627624"

def send_photo(path):
    url = f"https://api.telegram.org/bot{BOT_TOKEN}/sendPhoto"

    with open(path, "rb") as photo:
        requests.post(
            url,
            data={"chat_id": CHAT_ID},
            files={"photo": photo}
        )
