from fastapi import FastAPI

from database import engine
import models

app = FastAPI(title="Voice To Action API", version="1.0.0")


@app.on_event("startup")
def on_startup():
    models.Base.metadata.create_all(bind=engine)

@app.get("/")
def root():
    return {"mesaj": "Voice To Action Backend Sunucusu Başarıyla Çalışıyor! 🚀"}