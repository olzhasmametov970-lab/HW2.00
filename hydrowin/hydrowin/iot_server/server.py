from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates

app = FastAPI()
templates = Jinja2Templates(directory="templates")

# память (пока без БД для простоты)
data_store = {
    "temp": [],
    "press": [],
    "labels": []
}


@app.get("/")
def dashboard(request: Request):
    return templates.TemplateResponse("index.html", {"request": request})


@app.get("/data")
def receive_data(temp: float = 0, press: float = 0):

    from datetime import datetime

    if len(data_store["temp"]) > 50:
        data_store["temp"].pop(0)
        data_store["press"].pop(0)
        data_store["labels"].pop(0)

    data_store["temp"].append(temp)
    data_store["press"].append(press)
    data_store["labels"].append(datetime.now().strftime("%H:%M:%S"))

    return {"status": "ok"}


@app.get("/api/data")
def api():
    return data_store