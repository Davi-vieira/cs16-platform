import uuid
from datetime import datetime
from sqlalchemy import (
    Column, String, BigInteger, Integer, Boolean,
    ForeignKey, Text, JSON, UniqueConstraint, CheckConstraint
)
from sqlalchemy.dialects.postgresql import UUID, TIMESTAMPTZ, JSONB
from sqlalchemy.orm import DeclarativeBase, relationship


class Base(DeclarativeBase):
    pass


def new_uuid():
    return str(uuid.uuid4())


class Player(Base):
    __tablename__ = "players"

    id           = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    display_name = Column(String(64), nullable=False)
    level        = Column(Integer, nullable=False, default=1)
    xp           = Column(BigInteger, nullable=False, default=0)
    status       = Column(String(16), nullable=False, default="visitor")
    created_at   = Column(TIMESTAMPTZ, nullable=False, default=datetime.utcnow)
    updated_at   = Column(TIMESTAMPTZ, nullable=False, default=datetime.utcnow)

    identities   = relationship("PlayerIdentity", back_populates="player", cascade="all, delete")
    wallet       = relationship("Wallet", back_populates="player", uselist=False, cascade="all, delete")
    inventory    = relationship("InventoryItem", back_populates="player", cascade="all, delete")
    roles        = relationship("AdminRole", back_populates="player", cascade="all, delete")

    @property
    def rank(self) -> str:
        if self.level < 10:  return "Iniciante"
        if self.level < 25:  return "Amador"
        if self.level < 50:  return "Competente"
        if self.level < 75:  return "Veterano"
        return "Elite"


class PlayerIdentity(Base):
    __tablename__ = "player_identities"
    __table_args__ = (UniqueConstraint("provider", "external_id"),)

    id          = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    player_id   = Column(UUID(as_uuid=True), ForeignKey("players.id", ondelete="CASCADE"), nullable=False)
    provider    = Column(String(16), nullable=False)
    external_id = Column(String(64), nullable=False)
    verified_at = Column(TIMESTAMPTZ)

    player = relationship("Player", back_populates="identities")


class Wallet(Base):
    __tablename__ = "wallets"

    player_id  = Column(UUID(as_uuid=True), ForeignKey("players.id", ondelete="CASCADE"), primary_key=True)
    balance    = Column(BigInteger, nullable=False, default=0)
    updated_at = Column(TIMESTAMPTZ, nullable=False, default=datetime.utcnow)

    player       = relationship("Player", back_populates="wallet")
    transactions = relationship("WalletTransaction", back_populates="wallet")


class WalletTransaction(Base):
    __tablename__ = "wallet_transactions"

    id              = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    player_id       = Column(UUID(as_uuid=True), ForeignKey("players.id"), nullable=False)
    type            = Column(String(16), nullable=False)
    amount          = Column(BigInteger, nullable=False)
    currency        = Column(String(3), nullable=False, default="BRL")
    idempotency_key = Column(UUID(as_uuid=True), nullable=False, unique=True)
    reference_id    = Column(String(128), unique=True)
    reason          = Column(Text)
    admin_id        = Column(UUID(as_uuid=True), ForeignKey("players.id"))
    created_at      = Column(TIMESTAMPTZ, nullable=False, default=datetime.utcnow)

    wallet = relationship("Wallet", back_populates="transactions", foreign_keys=[player_id],
                          primaryjoin="WalletTransaction.player_id == Wallet.player_id")


class Item(Base):
    __tablename__ = "items"

    id            = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    sku           = Column(String(64), nullable=False, unique=True)
    display_name  = Column(String(128), nullable=False)
    item_type     = Column(String(24), nullable=False)
    price         = Column(BigInteger, nullable=False)
    asset_version = Column(String(32), nullable=False, default="1.0.0")
    enabled       = Column(Boolean, nullable=False, default=False)
    created_at    = Column(TIMESTAMPTZ, nullable=False, default=datetime.utcnow)


class InventoryItem(Base):
    __tablename__ = "inventory_items"

    player_id               = Column(UUID(as_uuid=True), ForeignKey("players.id", ondelete="CASCADE"), primary_key=True)
    item_id                 = Column(UUID(as_uuid=True), ForeignKey("items.id"), primary_key=True)
    acquired_transaction_id = Column(UUID(as_uuid=True), ForeignKey("wallet_transactions.id"))
    equipped                = Column(Boolean, nullable=False, default=False)

    player = relationship("Player", back_populates="inventory")
    item   = relationship("Item")


class PaymentOrder(Base):
    __tablename__ = "payment_orders"

    id                 = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    player_id          = Column(UUID(as_uuid=True), ForeignKey("players.id"), nullable=False)
    provider           = Column(String(32), nullable=False)
    provider_reference = Column(String(128), unique=True)
    amount             = Column(BigInteger, nullable=False)
    status             = Column(String(16), nullable=False, default="pending")
    webhook_payload    = Column(JSONB)
    created_at         = Column(TIMESTAMPTZ, nullable=False, default=datetime.utcnow)
    confirmed_at       = Column(TIMESTAMPTZ)


class AdminRole(Base):
    __tablename__ = "admin_roles"
    __table_args__ = (UniqueConstraint("player_id", "role"),)

    id         = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    player_id  = Column(UUID(as_uuid=True), ForeignKey("players.id", ondelete="CASCADE"), nullable=False)
    role       = Column(String(16), nullable=False)
    granted_by = Column(UUID(as_uuid=True), ForeignKey("players.id"))
    granted_at = Column(TIMESTAMPTZ, nullable=False, default=datetime.utcnow)
    revoked_at = Column(TIMESTAMPTZ)

    player = relationship("Player", back_populates="roles", foreign_keys=[player_id])


class AdminAuditLog(Base):
    __tablename__ = "admin_audit_logs"

    id          = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    admin_id    = Column(UUID(as_uuid=True), ForeignKey("players.id"), nullable=False)
    action      = Column(String(64), nullable=False)
    target_type = Column(String(32))
    target_id   = Column(UUID(as_uuid=True))
    payload     = Column(JSONB)
    created_at  = Column(TIMESTAMPTZ, nullable=False, default=datetime.utcnow)


class LinkCode(Base):
    __tablename__ = "link_codes"

    code       = Column(String(8), primary_key=True)
    player_id  = Column(UUID(as_uuid=True), ForeignKey("players.id", ondelete="CASCADE"), nullable=False)
    expires_at = Column(TIMESTAMPTZ, nullable=False)
    used_at    = Column(TIMESTAMPTZ)
