import uuid
from datetime import datetime
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from pydantic import BaseModel

from app.models.database import get_db
from app.models.models import Player, AdminRole, AdminAuditLog, Wallet, Item, PaymentOrder
from app.security.auth import require_role

router = APIRouter()


class RoleGrantIn(BaseModel):
    player_id: uuid.UUID
    role: str


class StatusUpdateIn(BaseModel):
    status: str
    reason: Optional[str] = None


class AuditLogOut(BaseModel):
    id: uuid.UUID
    admin_id: uuid.UUID
    action: str
    target_type: Optional[str]
    target_id: Optional[uuid.UUID]
    payload: Optional[dict]
    created_at: datetime

    class Config:
        from_attributes = True


class StatsOut(BaseModel):
    total_players: int
    total_items: int
    total_orders: int
    total_revenue_cents: int


@router.get("/stats", response_model=StatsOut)
async def get_stats(
    _: Player = Depends(require_role("administrator")),
    db: AsyncSession = Depends(get_db),
):
    players_count = await db.scalar(select(func.count(Player.id))) or 0
    items_count = await db.scalar(select(func.count(Item.id))) or 0
    orders_count = await db.scalar(select(func.count(PaymentOrder.id))) or 0
    revenue = await db.scalar(
        select(func.coalesce(func.sum(PaymentOrder.amount), 0)).where(
            PaymentOrder.status == "confirmed"
        )
    ) or 0

    return StatsOut(
        total_players=players_count,
        total_items=items_count,
        total_orders=orders_count,
        total_revenue_cents=revenue,
    )


@router.get("/audit-logs", response_model=list[AuditLogOut])
async def list_audit_logs(
    limit: int = Query(50, le=100),
    offset: int = 0,
    _: Player = Depends(require_role("administrator")),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(AdminAuditLog)
        .order_by(AdminAuditLog.created_at.desc())
        .offset(offset)
        .limit(limit)
    )
    return result.scalars().all()


@router.post("/roles/grant")
async def grant_role(
    body: RoleGrantIn,
    admin: Player = Depends(require_role("owner")),
    db: AsyncSession = Depends(get_db),
):
    valid_roles = {"support", "moderator", "administrator", "owner"}
    if body.role not in valid_roles:
        raise HTTPException(status_code=400, detail="Papel inválido")

    target = await db.get(Player, body.player_id)
    if not target:
        raise HTTPException(status_code=404, detail="Jogador não encontrado")

    role = AdminRole(
        player_id=body.player_id,
        role=body.role,
        granted_by=admin.id,
    )
    db.add(role)

    audit = AdminAuditLog(
        admin_id=admin.id,
        action="grant_role",
        target_type="player",
        target_id=body.player_id,
        payload={"role": body.role},
    )
    db.add(audit)

    await db.commit()
    return {"status": "role_granted", "player_id": body.player_id, "role": body.role}


@router.post("/roles/revoke")
async def revoke_role(
    body: RoleGrantIn,
    admin: Player = Depends(require_role("owner")),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(AdminRole).where(
            AdminRole.player_id == body.player_id,
            AdminRole.role == body.role,
            AdminRole.revoked_at.is_(None),
        )
    )
    role_obj = result.scalar_one_or_none()
    if not role_obj:
        raise HTTPException(status_code=404, detail="Papel não encontrado ou já revogado")

    role_obj.revoked_at = datetime.utcnow()

    audit = AdminAuditLog(
        admin_id=admin.id,
        action="revoke_role",
        target_type="player",
        target_id=body.player_id,
        payload={"role": body.role},
    )
    db.add(audit)

    await db.commit()
    return {"status": "role_revoked", "player_id": body.player_id, "role": body.role}


@router.patch("/players/{player_id}/status")
async def update_player_status(
    player_id: uuid.UUID,
    body: StatusUpdateIn,
    admin: Player = Depends(require_role("moderator")),
    db: AsyncSession = Depends(get_db),
):
    allowed_statuses = {"visitor", "linked", "verified", "suspended"}
    if body.status not in allowed_statuses:
        raise HTTPException(status_code=400, detail="Status inválido")

    target = await db.get(Player, player_id)
    if not target:
        raise HTTPException(status_code=404, detail="Jogador não encontrado")

    old_status = target.status
    target.status = body.status
    target.updated_at = datetime.utcnow()

    audit = AdminAuditLog(
        admin_id=admin.id,
        action="update_player_status",
        target_type="player",
        target_id=player_id,
        payload={"old_status": old_status, "new_status": body.status, "reason": body.reason},
    )
    db.add(audit)

    await db.commit()
    return {"player_id": player_id, "previous_status": old_status, "new_status": body.status}
