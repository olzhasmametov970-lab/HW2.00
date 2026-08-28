from sqlalchemy import Column, Integer, Float, DateTime
from datetime import datetime
from database import Base

class SensorData(Base):
    __tablename__ = "sensor_data"

    id = Column(Integer, primary_key=True, index=True)
    temp = Column(Float)
    press = Column(Float)
    created_at = Column(DateTime, default=datetime.utcnow)