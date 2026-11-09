from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from pydantic import BaseModel

from app.models.database import get_db
from app.models.models import Player, PlayerIdentity, AdminRole
from app.security.auth import verify_password, create_access_token

router = APIRouter()


class Token(BaseModel):
    access_token: str
    token_type: str = "bearer"


@router.post("/login", response_model=Token)
async def login(
    form: OAuth2PasswordRequestForm = Depends(),
    db: AsyncSession = Depends(get_db),
):
    # Login por external_id do provider 'web' (email como external_id)
    result = await db.execute(
        select(PlayerIdentity).where(
            PlayerIdentity.provider == "web",
            PlayerIdentity.external_id == form.username,
        )
    )
    identity = result.scalar_one_or_none()
    if not identity:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Credenciais inválidas")

    player = await db.get(Player, identity.player_id)
    if not player or player.status == "suspended":
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Conta suspensa ou inexistente")

    # Busca o hash da senha armazenado no provider 'web_password'
    pass_result = await db.execute(
        select(PlayerIdentity).where(
            PlayerIdentity.player_id == player.id,
            PlayerIdentity.provider == "web_password",
        )
    )
    pass_identity = pass_result.scalar_one_or_none()
    if not pass_identity or not verify_password(form.password, pass_identity.external_id):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Credenciais inválidas")

    roles_result = await db.execute(
        select(AdminRole).where(
            AdminRole.player_id == player.id,
            AdminRole.revoked_at.is_(None)
        )
    )
    roles = [r.role for r in roles_result.scalars().all()]

    token = create_access_token(str(player.id), roles)
    return Token(access_token=token)
