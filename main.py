import os
import re
# FFMPEG adresini Python'a zorla öğretiyoruz
os.environ["PATH"] += os.pathsep + r"C:\ffmpeg\bin"

import whisper  # Whisper importunun bu satırdan SONRA olması çok önemli!
import shutil
import uuid

from fastapi import Depends, FastAPI, File, Form, HTTPException, UploadFile, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy.orm import Session

from database import engine, get_db
import models
import schemas

app = FastAPI(title="Voice To Action API", version="1.0.0")
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
whisper_model = whisper.load_model("base")

# ---------------------------------------------------------------------------
# NLP: Türkçe kural tabanlı görev & tarih çıkarıcı  (False-Positive azaltılmış)
# ---------------------------------------------------------------------------

# Katı zorunlu anahtar kelimeler: en az biri MUTLAKA bulunmalı.
_REQUIRED_TASK_KEYWORDS: list[str] = [
    "lazım", "gerek", "gerekiyor", "gerekli",
    "yapılacak", "yapılmalı", "yapılması",
    "teslim", "teslim et", "teslim edilecek",
    "unutma", "unutmayın",
    "toplantı", "rapor", "görev", "ödev",
    "hazırla", "hazırlayın", "hazırlanacak",
    "gönder", "gönderilecek", "iletilecek",
    "tamamla", "tamamlanacak", "bitirilecek",
    "planla", "organize et",
    "takip et", "kontrol et",
    "sunum", "proje teslim",
]

# Cümle başından temizlenecek bağlaç/gürültü kalıpları.
# Not: re.UNICODE ile Türkçe karakterler güvenli işlenir.
_NOISE_RE = re.compile(
    r"^(ve\s+|bir\s+|ama\s+|fakat\s+|"
    r"ki\s+|da\s+|de\s+|ile\s+|"
    r"yani\s+|zaten\s+|"
    r"o\s+zaman\s+|belki\s+|herhalde\s+)+",
    re.IGNORECASE | re.UNICODE,
)

_DATE_MAP: dict[str, str] = {
    "bugün": "Bugün",
    "yarın": "Yarın",
    "öbür gün": "Öbür gün",
    "haftaya": "Haftaya",
    "bu hafta": "Bu hafta",
    "gelecek hafta": "Gelecek hafta",
    "pazartesi": "Pazartesi",
    "salı": "Salı",
    "çarşamba": "Çarşamba",
    "perşembe": "Perşembe",
    "cuma": "Cuma",
    "cumartesi": "Cumartesi",
    "pazar": "Pazar",
    "ocak": "Ocak", "şubat": "Şubat", "mart": "Mart",
    "nisan": "Nisan", "mayıs": "Mayıs", "haziran": "Haziran",
    "temmuz": "Temmuz", "ağustos": "Ağustos", "eylül": "Eylül",
    "ekim": "Ekim", "kasım": "Kasım", "aralık": "Aralık",
}

# "3 gün sonra", "2 hafta sonra" gibi dinamik tarih ifadeleri
_RELATIVE_DATE_RE = re.compile(r"\d+\s*(gün|hafta|ay)\s*sonra", re.IGNORECASE | re.UNICODE)

# En az kaç kelime içermesi gerekiyor
_MIN_WORD_COUNT = 3


def _clean_sentence(sentence: str) -> str:
    """Cümle başındaki gürültü bağlaçlarını temizler."""
    return _NOISE_RE.sub("", sentence).strip()


def extract_tasks_from_text(text: str) -> list[dict]:
    """
    Metinden kural tabanlı görev ve tarih bilgisi çıkarır.

    Bir cümle görev sayılmak için:
      1) _REQUIRED_TASK_KEYWORDS içinden en az bir keyword içermeli.
      2) Bağlaç temizliği sonrası en az _MIN_WORD_COUNT kelimeden oluşmalı.
    """
    sentences = re.split(r"[.!?;\n]+", text)
    tasks: list[dict] = []
    seen: set[str] = set()

    for raw_sentence in sentences:
        sentence = raw_sentence.strip()
        if not sentence:
            continue

        lower = sentence.lower()

        # Kural 1: Katı keyword kontrolü
        if not any(kw in lower for kw in _REQUIRED_TASK_KEYWORDS):
            continue

        # Cümleyi bağlaçlardan temizle
        cleaned = _clean_sentence(sentence)

        # Kural 2: Minimum kelime sayısı kontrolü (temizlenmiş hali üzerinden)
        word_count = len(cleaned.split())
        if word_count < _MIN_WORD_COUNT:
            continue

        # Aynı görev metnini tekrar ekleme
        key = cleaned.lower()
        if key in seen:
            continue
        seen.add(key)

        # Tarih tespiti
        due_date: str = "Belirtilmedi"
        for date_kw, label in _DATE_MAP.items():
            if date_kw in lower:
                due_date = label
                break

        if due_date == "Belirtilmedi":
            match = _RELATIVE_DATE_RE.search(lower)
            if match:
                due_date = match.group(0).capitalize()

        tasks.append({
            "task_title": cleaned[:200],
            "due_date": due_date,
        })

    return tasks

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
#@app.on_event("startup")
def on_startup():
    models.Base.metadata.drop_all(bind=engine) # Başındaki # işaretini kaldır
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
        "user_id": user.id,
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
async def transcribe(
    file: UploadFile = File(...),
    category: str = Form("genel"),
    user_id: int = Form(...),
    db: Session = Depends(get_db),
):
    temp_file_path = "temp_audio_video_file"
    try:
        # 1) Geçici dosyaya yaz
        with open(temp_file_path, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)

        # 2) Whisper ile metne çevir (FFMPEG ses/video ayrıştırır)
        result = whisper_model.transcribe(temp_file_path)
        transcribed_text: str = result["text"]

        # 3) records tablosuna kaydet
        db_record = models.Record(
            user_id=user_id,
            filename=file.filename or "bilinmiyor",
            category=category,
            status="tamamlandi",
            transcribed_text=transcribed_text,
        )
        db.add(db_record)
        db.commit()
        db.refresh(db_record)

        # 4) NLP ile görevleri çıkar
        extracted_tasks = extract_tasks_from_text(transcribed_text)

        # 5) Her görevi tasks tablosuna kaydet
        for task_data in extracted_tasks:
            db_task = models.Task(
                record_id=db_record.id,
                title=task_data["task_title"][:255],
                deadline=None,
                is_completed=False,
            )
            db.add(db_task)
        db.commit()

        # 6) Zenginleştirilmiş yanıtı dön
        return {
            "text": transcribed_text,
            "record_id": db_record.id,
            "tasks": extracted_tasks,
        }
    finally:
        await file.close()
        if os.path.exists(temp_file_path):
            os.remove(temp_file_path)


@app.get("/api/records/{user_id}")
def get_user_records(user_id: int, db: Session = Depends(get_db)):
    """Kullanıcıya ait tüm transkripsiyon kayıtlarını döner."""
    records = (
        db.query(models.Record)
        .filter(models.Record.user_id == user_id)
        .order_by(models.Record.id.desc())
        .all()
    )
    return [
        {
            "id": r.id,
            "file_name": r.filename,
            "category": r.category or "Diğer",
            "transcript": r.transcribed_text or "",
            "status": r.status,
        }
        for r in records
    ]


@app.get("/api/tasks/{user_id}")
def get_user_tasks(user_id: int, db: Session = Depends(get_db)):
    """Kullanıcının tüm kayıtlarına ait NLP görevlerini döner."""
    record_ids = [
        r.id
        for r in db.query(models.Record.id)
        .filter(models.Record.user_id == user_id)
        .all()
    ]
    if not record_ids:
        return []
    tasks = (
        db.query(models.Task)
        .filter(models.Task.record_id.in_(record_ids))
        .order_by(models.Task.id.desc())
        .all()
    )
    return [
        {
            "id": t.id,
            "record_id": t.record_id,
            "title": t.title,
            "due_date": str(t.deadline) if t.deadline else None,
            "status": "done" if t.is_completed else "pending",
        }
        for t in tasks
    ]


@app.put("/api/update-profile")
def update_profile(newName: str, email: str, db: Session = Depends(get_db)):
    user = db.query(models.User).filter(models.User.email == email).first()
    if user is None:
        raise HTTPException(status_code=404, detail="Kullanici bulunamadi")

    user.full_name = newName
    db.commit()
    db.refresh(user)
    return {"message": "Profil güncellendi"}