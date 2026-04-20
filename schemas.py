from pydantic import BaseModel, ConfigDict


class UserRegister(BaseModel):
    full_name: str
    email: str
    password: str


class UserOut(BaseModel):
    id: int
    full_name: str
    email: str

    model_config = ConfigDict(from_attributes=True)


class Token(BaseModel):
    access_token: str
    token_type: str
    full_name: str | None = None
    user_id: int | None = None
