from sqlalchemy import create_engine
from sqlalchemy.orm import declarative_base, sessionmaker

# ── Bağlantı URL'si ──────────────────────────────────────────────────────────
SQLALCHEMY_DATABASE_URL = "postgresql://postgres:194001@127.0.0.1:5432/voicetoaction_db"

# ── Engine ───────────────────────────────────────────────────────────────────
# pool_pre_ping=True → bağlantı kopmuşsa otomatik yenile; "server closed the
# connection unexpectedly" hatasını önler.
engine = create_engine(
    SQLALCHEMY_DATABASE_URL,
    pool_pre_ping=True,
)

# ── Session fabrikası ─────────────────────────────────────────────────────────
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

# ── Model tabanı ──────────────────────────────────────────────────────────────
Base = declarative_base()


# ── FastAPI bağımlılığı: her istek → yeni session → garantili kapat ──────────
def get_db():
    db = SessionLocal()
    try:
        yield db
    except Exception:
        db.rollback()   # yarım işlemi geri al; üst katman hatayı yeniden fırlatır
        raise
    finally:
        db.close()      # her durumda bağlantıyı havuza iade et
