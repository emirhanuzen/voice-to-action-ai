from sqlalchemy import create_engine
from sqlalchemy.orm import declarative_base, sessionmaker

# Dummy PostgreSQL bağlantı URL'si
SQLALCHEMY_DATABASE_URL = "postgresql://postgres:194001@localhost:5432/voicetoaction_db"

# SQLAlchemy engine objesini oluşturuyoruz
engine = create_engine(SQLALCHEMY_DATABASE_URL)

# Veritabanı oturumlarını yönetmek için SessionLocal sınıfı
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

# Modellerimizin miras alacağı temel sınıf
Base = declarative_base()

# FastAPI bağımlılığı (dependency) olarak veritabanı oturumu sağlayan fonksiyon
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
