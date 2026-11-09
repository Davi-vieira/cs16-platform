import uuid
from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from pydantic import BaseModel

from app.models.database import get_db
from app.models.models import Player, PaymentOrder, Wallet, WalletTransaction
from app.security.auth import get_current_player

router = APIRouter()


class PaymentOrderIn(BaseModel):
    amount: int      # centavos
    provider: str


class PaymentOrderOut(BaseModel):
    id: uuid.UUID
    amount: int
    status: str
    created_at: datetime

    class Config:
        from_attributes = True


@router.post("/orders", response_model=PaymentOrderOut)
async def create_order(
    body: PaymentOrderIn,
    current: Player = Depends(get_current_player),
    db: AsyncSession = Depends(get_db),
):
    if body.amount <= 0:
        raise HTTPException(status_code=400, detail="Valor deve ser positivo")
    if body.amount > 100_000_00:  # limite R$ 100.000
        raise HTTPException(status_code=400, detail="Valor acima do limite permitido")

    order = PaymentOrder(
        player_id=current.id,
        provider=body.provider,
        amount=body.amount,
    )
    db.add(order)
    await db.commit()
    await db.refresh(order)
    return order


@router.get("/orders", response_model=list[PaymentOrderOut])
async def list_orders(
    current: Player = Depends(get_current_player),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(PaymentOrder)
        .where(PaymentOrder.player_id == current.id)
        .order_by(PaymentOrder.created_at.desc())
        .limit(20)
    )
    return result.scalars().all()
