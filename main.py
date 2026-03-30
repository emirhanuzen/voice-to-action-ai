import os
# FFMPEG adresini Python'a zorla öğretiyoruz
os.environ["PATH"] += os.pathsep + r"C:\ffmpeg\bin"

import whisper  # Whisper importunun bu satırdan SONRA olması çok önemli!
import shutil
import uuid

from fastapi import Depends, FastAPI, File, HTTPException, UploadFile, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy.orm import Session

from database import engine, get_db
import models
import schemas

app = FastAPI(title="Voice To Action API", version="1.0.0")
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
whisper_model = whisper.load_model("base")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
@app.on_event("startup")
def on_startup():
    # NÜKLEER BOMBA İPTAL EDİLDİ: Artık hesaplar silinmeyecek!
    # models.Base.metadata.drop_all(bind=engine) 
    
    # Sadece eksik tablo varsa oluşturur, olanlara DOKUNMAZ:
    models.Base.metadata.create_all(bind=engine)
    
@app.get("/")
def root():
    return {"mesaj": "Voice To Action Backend Sunucusu Başarıyla Çalışıyor! 🚀"}


@app.post("/api/register", response_model=schemas.UserOut, status_code=status.HTTP_201_CREATED)
def register(user: schemas.UserRegister, db: Session = Depends(get_db)):
    existing_user = db.query(models.User).filter(models.User.email == user.email).first()
    if existing_user:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Bu email ile kayıtlı bir kullanıcı zaten var.",
        )

    db_user = models.User(
        full_name=user.full_name,
        email=user.email,
        password=user.password,
    )
    db.add(db_user)
    db.commit()
    db.refresh(db_user)
    return db_user


@app.post("/api/login", response_model=schemas.Token)
def login(form_data: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(get_db)):
    user = (
        db.query(models.User)
        .filter(
            models.User.email == form_data.username,
            models.User.password == form_data.password,
        )
        .first()
    )
    if not user:
        raise HTTPException(status_code=401, detail="Hatalı şifre veya email")

    return {
        "access_token": "token123",
        "token_type": "bearer",
        "full_name": user.full_name,
    }


@app.post("/upload-audio/")
async def upload_audio(file: UploadFile = File(...)):
    upload_dir = os.path.join(BASE_DIR, "uploads")
    os.makedirs(upload_dir, exist_ok=True)

    unique_filename = f"{uuid.uuid4().hex}_{os.path.basename(file.filename)}"
    file_path = os.path.join(upload_dir, unique_filename)

    with open(file_path, "wb") as buffer:
        shutil.copyfileobj(file.file, buffer)

    await file.close()

    return {
        "message": "Ses dosyasi basariyla yuklendi.",
        "file_path": file_path,
    }


@app.post("/api/transcribe")
async def transcribe(file: UploadFile = File(...)):
    temp_file_path = "temp_audio_video_file"
    try:
        with open(temp_file_path, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)

        result = whisper_model.transcribe(temp_file_path)
        return {"text": result["text"]}
    finally:
        await file.close()
        if os.path.exists(temp_file_path):
            os.remove(temp_file_path)


@app.put("/api/update-profile")
def update_profile(newName: str, email: str, db: Session = Depends(get_db)):
    user = db.query(models.User).filter(models.User.email == email).first()
    if user is None:
        raise HTTPException(status_code=404, detail="Kullanici bulunamadi")

    user.full_name = newName
    db.commit()
    db.refresh(user)
    return {"message": "Profil güncellendi"}