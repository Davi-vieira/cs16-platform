import os
import secrets
from datetime import datetime, timedelta
from typing import Optional

from jose import JWTError, jwt
from passlib.context import CryptContext
from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.models.database import get_db
from app.models.models import Player, AdminRole

SECRET_KEY   = os.environ.get("SECRET_KEY", "vieira_strike_default_secret_key_change_in_prod")
ALGORITHM    = "HS256"
TOKEN_EXPIRE = 60  # minutos

pwd_context = CryptContext(schemes=["argon2"], deprecated="auto")
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/auth/login")

ROLE_HIERARCHY = ["support", "moderator", "administrator", "owner"]


def hash_password(password: str) -> str:
    return pwd_context.hash(password)


def verify_password(plain: str, hashed: str) -> bool:
    return pwd_context.verify(plain, hashed)


def create_access_token(player_id: str, roles: list[str]) -> str:
    expire = datetime.utcnow() + timedelta(minutes=TOKEN_EXPIRE)
    return jwt.encode(
        {"sub": player_id, "roles": roles, "exp": expire},
        SECRET_KEY, algorithm=ALGORITHM
    )


async def get_current_player(
    token: str = Depends(oauth2_scheme),
    db: AsyncSession = Depends(get_db),
) -> Player:
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Token inválido ou expirado",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        player_id: str = payload.get("sub")
        if not player_id:
            raise credentials_exception
    except JWTError:
        raise credentials_exception

    result = await db.execute(select(Player).where(Player.id == player_id))
    player = result.scalar_one_or_none()
    if not player or player.status == "suspended":
        raise credentials_exception
    return player


def require_role(minimum_role: str):
    async def checker(
        current: Player = Depends(get_current_player),
        db: AsyncSession = Depends(get_db),
    ) -> Player:
        result = await db.execute(
            select(AdminRole).where(
                AdminRole.player_id == current.id,
                AdminRole.revoked_at.is_(None)
            )
        )
        roles = [r.role for r in result.scalars().all()]
        min_idx = ROLE_HIERARCHY.index(minimum_role)
        has_role = any(
            ROLE_HIERARCHY.index(r) >= min_idx
            for r in roles if r in ROLE_HIERARCHY
        )
        if not has_role:
            raise HTTPException(status_code=403, detail="Permissão insuficiente")
        return current
    return checker


def generate_link_code() -> str:
    return secrets.token_urlsafe(6)[:8].upper()
