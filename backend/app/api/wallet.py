import uuid
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from pydantic import BaseModel
from datetime import datetime

from app.models.database import get_db
from app.models.models import Player, Wallet, WalletTransaction, AdminAuditLog
from app.security.auth import get_current_player, require_role

router = APIRouter()


class WalletOut(BaseModel):
    balance: int
    updated_at: datetime

    class Config:
        from_attributes = True


class TransactionOut(BaseModel):
    id: uuid.UUID
    type: str
    amount: int
    currency: str
    created_at: datetime

    class Config:
        from_attributes = True


class AdjustmentIn(BaseModel):
    player_id: uuid.UUID
    amount: int       # positivo ou negativo, em centavos
    reason: str


@router.get("/me", response_model=WalletOut)
async def get_my_wallet(
    current: Player = Depends(get_current_player),
    db: AsyncSession = Depends(get_db),
):
    wallet = await db.get(Wallet, current.id)
    if not wallet:
        raise HTTPException(status_code=404, detail="Carteira não encontrada")
    return wallet


@router.get("/me/transactions", response_model=list[TransactionOut])
async def get_my_transactions(
    current: Player = Depends(get_current_player),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(WalletTransaction)
        .where(WalletTransaction.player_id == current.id)
        .order_by(WalletTransaction.created_at.desc())
        .limit(50)
    )
    return result.scalars().all()


@router.post("/adjust")
async def adjust_balance(
    body: AdjustmentIn,
    admin: Player = Depends(require_role("administrator")),
    db: AsyncSession = Depends(get_db),
):
    """Ajuste manual de saldo — exige papel administrator ou superior.
    Gera log de auditoria imutável conforme regra 5 da auditoria."""
    if not body.reason or len(body.reason.strip()) < 5:
        raise HTTPException(status_code=400, detail="Motivo obrigatório (mínimo 5 caracteres)")

    wallet = await db.get(Wallet, body.player_id)
    if not wallet:
        raise HTTPException(status_code=404, detail="Carteira não encontrada")

    new_balance = wallet.balance + body.amount
    if new_balance < 0:
        raise HTTPException(status_code=400, detail="Saldo não pode ficar negativo")

    wallet.balance = new_balance

    tx = WalletTransaction(
        player_id=body.player_id,
        type="adjustment",
        amount=body.amount,
        idempotency_key=uuid.uuid4(),
        reason=body.reason,
        admin_id=admin.id,
    )
    db.add(tx)

    log = AdminAuditLog(
        admin_id=admin.id,
        action="wallet_adjustment",
        target_type="player",
        target_id=body.player_id,
        payload={"amount": body.amount, "reason": body.reason},
    )
    db.add(log)

    await db.commit()
    return {"balance": wallet.balance}
