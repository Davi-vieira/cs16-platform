from datetime import datetime, timedelta
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from pydantic import BaseModel
import uuid

from app.models.database import get_db
from app.models.models import Player, LinkCode
from app.security.auth import get_current_player, generate_link_code

router = APIRouter()


class PlayerOut(BaseModel):
    id: uuid.UUID
    display_name: str
    level: int
    xp: int
    rank: str
    status: str

    class Config:
        from_attributes = True


class LinkCodeOut(BaseModel):
    code: str
    expires_at: datetime


@router.get("/me", response_model=PlayerOut)
async def get_me(current: Player = Depends(get_current_player)):
    return current


@router.get("/{player_id}", response_model=PlayerOut)
async def get_player(
    player_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    _: Player = Depends(get_current_player),
):
    player = await db.get(Player, player_id)
    if not player:
        raise HTTPException(status_code=404, detail="Jogador não encontrado")
    return player


@router.post("/me/link-code", response_model=LinkCodeOut)
async def gerar_link_code(
    current: Player = Depends(get_current_player),
    db: AsyncSession = Depends(get_db),
):
    code = generate_link_code()
    expires = datetime.utcnow() + timedelta(minutes=15)
    link = LinkCode(code=code, player_id=current.id, expires_at=expires)
    db.add(link)
    await db.commit()
    return LinkCodeOut(code=code, expires_at=expires)
