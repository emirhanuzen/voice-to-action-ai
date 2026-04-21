from datetime import datetime, timedelta, timezone
from typing import Any

from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from jose import JWTError, jwt
from passlib.context import CryptContext
from sqlalchemy.orm import Session

from database import get_db
import models

# ── Güvenlik sabitleri ──────────────────────────────────────────────────────
SECRET_KEY = "voicetoaction-jwt-secret-key-change-in-production-2026"
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 24  # 24 saat

# ── Passlib bcrypt bağlamı ──────────────────────────────────────────────────
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

# ── OAuth2 şeması: tokenUrl login endpoint'ini işaret eder ─────────────────
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/login")


# ── Şifre yardımcıları ──────────────────────────────────────────────────────
def get_password_hash(password: str) -> str:
    """Düz metin şifreyi bcrypt ile hashler."""
    return pwd_context.hash(password)


def verify_password(plain_password: str, hashed_password: str) -> bool:
    """Düz metin ile hash'i karşılaştırır."""
    return pwd_context.verify(plain_password, hashed_password)


# ── JWT token üreteci ───────────────────────────────────────────────────────
def create_access_token(
    data: dict[str, Any],
    expires_delta: timedelta | None = None,
) -> str:
    """
    Verilen payload'ı imzalayarak JWT access token döner.
    'sub' alanına kullanıcı e-postası yazılmalıdır.
    """
    to_encode = data.copy()
    expire = datetime.now(timezone.utc) + (
        expires_delta if expires_delta else timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    )
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)


# ── FastAPI Dependency: mevcut kullanıcıyı token'dan çöz ───────────────────
def get_current_user(
    token: str = Depends(oauth2_scheme),
    db: Session = Depends(get_db),
) -> models.User:
    """
    Authorization: Bearer <token> header'ından kullanıcıyı doğrular.
    Geçersiz veya süresi dolmuş token → 401 HTTP hatası.
    """
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Kimlik doğrulama başarısız veya token süresi dolmuş.",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        email: str | None = payload.get("sub")
        if email is None:
            raise credentials_exception
    except JWTError:
        raise credentials_exception

    user = db.query(models.User).filter(models.User.email == email).first()
    if user is None:
        raise credentials_exception
    return user
