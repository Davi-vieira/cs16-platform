import uuid
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from pydantic import BaseModel
from datetime import datetime

from app.models.database import get_db
from app.models.models import Item, Player
from app.security.auth import get_current_player, require_role

router = APIRouter()


class ItemOut(BaseModel):
    id: uuid.UUID
    sku: str
    display_name: str
    item_type: str
    price: int
    asset_version: str
    enabled: bool

    class Config:
        from_attributes = True


class ItemIn(BaseModel):
    sku: str
    display_name: str
    item_type: str
    price: int
    asset_version: str = "1.0.0"


@router.get("/", response_model=list[ItemOut])
async def list_items(db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(Item).where(Item.enabled == True).order_by(Item.price)
    )
    return result.scalars().all()


@router.post("/", response_model=ItemOut)
async def create_item(
    body: ItemIn,
    _: Player = Depends(require_role("administrator")),
    db: AsyncSession = Depends(get_db),
):
    if body.price < 0:
        raise HTTPException(status_code=400, detail="Preço não pode ser negativo")
    item = Item(**body.model_dump())
    db.add(item)
    await db.commit()
    await db.refresh(item)
    return item


@router.patch("/{item_id}/toggle")
async def toggle_item(
    item_id: uuid.UUID,
    _: Player = Depends(require_role("administrator")),
    db: AsyncSession = Depends(get_db),
):
    item = await db.get(Item, item_id)
    if not item:
        raise HTTPException(status_code=404, detail="Item não encontrado")
    item.enabled = not item.enabled
    await db.commit()
    return {"enabled": item.enabled}
