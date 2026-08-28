from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse
import uvicorn
import time

app = FastAPI()

# ---------------- DATA STORAGE ----------------
temps = []
pressures = []
times = []

MAX_POINTS = 50

# ---------------- RECEIVE DATA ----------------
@app.get("/data")
async def receive_data(temp: float, press: float):

    current_time = time.strftime("%H:%M:%S")

    temps.append(temp)
    pressures.append(press)
    times.append(current_time)

    if len(temps) > MAX_POINTS:
        temps.pop(0)
        pressures.pop(0)
        times.pop(0)

    return {"status": "ok"}

# ---------------- API FOR CHART ----------------
@app.get("/get_data")
async def get_data():
    return {
        "temps": temps,
        "pressures": pressures,
        "times": times
    }

# ---------------- WEB PAGE ----------------
@app.get("/", response_class=HTMLResponse)
async def dashboard():

    return """
<!DOCTYPE html>
<html>

<head>
    <title>PLC SCADA</title>

    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>

    <style>

        body{
            background:#111;
            color:white;
            font-family:Arial;
            padding:20px;
        }

        h1{
            text-align:center;
        }

        .chart-box{
            background:#1b1b1b;
            padding:20px;
            margin-bottom:30px;
            border-radius:10px;
        }

        canvas{
            background:#222;
            border-radius:10px;
        }

    </style>
</head>

<body>

<h1>PLC SCADA Dashboard</h1>

<div class="chart-box">
    <h2>Temperature</h2>
    <canvas id="tempChart"></canvas>
</div>

<div class="chart-box">
    <h2>Pressure</h2>
    <canvas id="pressChart"></canvas>
</div>

<script>

const tempCtx = document.getElementById('tempChart');

const pressCtx = document.getElementById('pressChart');

const tempChart = new Chart(tempCtx, {

    type: 'line',

    data: {
        labels: [],
        datasets: [{
            label: 'Temperature °C',
            data: [],
            borderColor: 'red',
            borderWidth: 2,
            tension: 0.2
        }]
    },

    options: {
        responsive: true,
        scales: {
            y: {
                beginAtZero: false
            }
        }
    }
});

const pressChart = new Chart(pressCtx, {

    type: 'line',

    data: {
        labels: [],
        datasets: [{
            label: 'Pressure MPa',
            data: [],
            borderColor: 'cyan',
            borderWidth: 2,
            tension: 0.2
        }]
    },

    options: {
        responsive: true,
        scales: {
            y: {
                beginAtZero: true
            }
        }
    }
});

async function updateCharts(){

    const response = await fetch('/get_data');
    const data = await response.json();

    tempChart.data.labels = data.times;
    tempChart.data.datasets[0].data = data.temps;
    tempChart.update();

    pressChart.data.labels = data.times;
    pressChart.data.datasets[0].data = data.pressures;
    pressChart.update();
}

setInterval(updateCharts, 2000);

</script>

</body>
</html>
"""

# ---------------- START SERVER ----------------
if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)