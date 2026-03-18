from sqlalchemy import Column, Integer, String, Boolean, ForeignKey, DateTime
from sqlalchemy.orm import relationship
from database import Base

class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    email = Column(String, unique=True, index=True, nullable=False)
    hashed_password = Column(String, nullable=False)

    # User'ın Record'ları ile ilişkisi (Bire-Çok)
    records = relationship("Record", back_populates="owner", cascade="all, delete-orphan")


class Record(Base):
    __tablename__ = "records"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    filename = Column(String, nullable=False)
    category = Column(String)
    status = Column(String, default="pending")

    # Record'ın sahibi olan User ile ilişkisi
    owner = relationship("User", back_populates="records")
    
    # Record'ın Task'ları ile ilişkisi (Bire-Çok)
    tasks = relationship("Task", back_populates="record", cascade="all, delete-orphan")


class Task(Base):
    __tablename__ = "tasks"

    id = Column(Integer, primary_key=True, index=True)
    record_id = Column(Integer, ForeignKey("records.id"), nullable=False)
    title = Column(String, nullable=False)
    deadline = Column(DateTime)
    is_completed = Column(Boolean, default=False)

    # Task'ın bağlı olduğu Record ile ilişkisi
    record = relationship("Record", back_populates="tasks")
