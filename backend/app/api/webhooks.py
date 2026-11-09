import os
import hmac
import hashlib
import uuid
from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException, Request, Header
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.models.database import get_db
from app.models.models import PaymentOrder, Wallet, WalletTransaction

router = APIRouter()

WEBHOOK_SECRET = os.environ.get("PAYMENT_WEBHOOK_SECRET", "vieira_strike_webhook_secret_change_in_prod")


def verify_signature(payload: bytes, signature: str) -> bool:
    expected = hmac.new(WEBHOOK_SECRET.encode(), payload, hashlib.sha256).hexdigest()
    return hmac.compare_digest(expected, signature)


@router.post("/payment")
async def payment_webhook(
    request: Request,
    x_signature: str = Header(..., alias="X-Signature"),
    db: AsyncSession = Depends(get_db),
):
    body = await request.body()

    if not verify_signature(body, x_signature):
        raise HTTPException(status_code=401, detail="Assinatura inválida")

    data = await request.json()
    provider_reference = data.get("reference")
    status_received    = data.get("status")
    amount_received    = data.get("amount")  # centavos

    if not provider_reference or not status_received:
        raise HTTPException(status_code=400, detail="Payload incompleto")

    # Busca pedido pelo provider_reference
    result = await db.execute(
        select(PaymentOrder).where(PaymentOrder.provider_reference == provider_reference)
    )
    order = result.scalar_one_or_none()

    if not order:
        # Tenta associar pelo id interno se o provider ainda não tinha referência
        order_id = data.get("order_id")
        if order_id:
            order = await db.get(PaymentOrder, order_id)
        if not order:
            raise HTTPException(status_code=404, detail="Pedido não encontrado")
        order.provider_reference = provider_reference

    # Idempotência — já confirmado, retorna 200 sem reprocessar
    if order.status == "confirmed":
        return {"ok": True, "idempotent": True}

    if status_received != "confirmed":
        order.status = status_received
        order.webhook_payload = data
        await db.commit()
        return {"ok": True}

    # Valida valor — nunca creditar valor diferente do pedido
    if amount_received != order.amount:
        raise HTTPException(status_code=400, detail="Valor divergente do pedido")

    # Confirma pedido e credita carteira em transação atômica
    order.status       = "confirmed"
    order.confirmed_at = datetime.utcnow()
    order.webhook_payload = data

    wallet = await db.get(Wallet, order.player_id)
    if not wallet:
        raise HTTPException(status_code=500, detail="Carteira não encontrada")

    wallet.balance += order.amount

    tx = WalletTransaction(
        player_id=order.player_id,
        type="topup",
        amount=order.amount,
        idempotency_key=uuid.uuid4(),
        reference_id=provider_reference,
    )
    db.add(tx)
    await db.commit()

    return {"ok": True}
