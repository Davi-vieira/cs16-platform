"""
scripts/seed.py — Popula o banco com catálogo inicial e usuário administrador (owner)
Uso:
    python -m scripts.seed
"""

import asyncio
import os
import uuid
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncSession
from sqlalchemy import select

from app.models.models import Base, Player, PlayerIdentity, AdminRole, Item, Wallet
from app.security.auth import hash_password

DATABASE_URL = os.environ.get(
    "DATABASE_URL",
    "postgresql+asyncpg://cs16_admin:cs16_secret@localhost:5432/cs16"
)

engine = create_async_engine(DATABASE_URL, echo=True)
SessionLocal = async_sessionmaker(engine, expire_on_commit=False, class_=AsyncSession)


async def seed():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    async with SessionLocal() as db:
        # 1. Cria usuário Admin (Owner) se não existir
        admin_email = os.environ.get("ADMIN_DEFAULT_EMAIL", "admin@vieirastrike.com")
        admin_pass = os.environ.get("ADMIN_DEFAULT_PASSWORD", "AdminVieira2026!")

        res = await db.execute(
            select(PlayerIdentity).where(
                PlayerIdentity.provider == "web",
                PlayerIdentity.external_id == admin_email
            )
        )
        existing_identity = res.scalar_one_or_none()

        if not existing_identity:
            print(f"[Seed] Criando usuário Owner ({admin_email})...")
            admin_player = Player(
                display_name="Vieira (Owner)",
                level=100,
                xp=50000,
                status="verified"
            )
            db.add(admin_player)
            await db.flush()

            identity_web = PlayerIdentity(
                player_id=admin_player.id,
                provider="web",
                external_id=admin_email
            )
            db.add(identity_web)

            # Armazena hash da senha
            identity_pass = PlayerIdentity(
                player_id=admin_player.id,
                provider="web_password",
                external_id=hash_password(admin_pass)
            )
            db.add(identity_pass)

            # Papel Owner
            role_owner = AdminRole(
                player_id=admin_player.id,
                role="owner"
            )
            db.add(role_owner)

            # Carteira inicial
            wallet = Wallet(player_id=admin_player.id, balance=100000) # R$ 1.000,00
            db.add(wallet)

            print(f"[Seed] Owner criado com sucesso! Senha padrão: {admin_pass}")
        else:
            print("[Seed] Usuário Owner já existe.")

        # 2. Catálogo de Itens Inicial
        initial_items = [
            {
                "sku": "skin_ak47_vulcan",
                "display_name": "AK-47 Vulcan",
                "item_type": "weapon_skin",
                "price": 2500,  # R$ 25,00
                "asset_version": "1.0.0",
                "enabled": True
            },
            {
                "sku": "skin_m4a1_hyperbeast",
                "display_name": "M4A1 Hyper Beast",
                "item_type": "weapon_skin",
                "price": 2000,  # R$ 20,00
                "asset_version": "1.0.0",
                "enabled": True
            },
            {
                "sku": "model_player_arctic_elite",
                "display_name": "Arctic Avengers Elite",
                "item_type": "player_model",
                "price": 1500,  # R$ 15,00
                "asset_version": "1.0.0",
                "enabled": True
            }
        ]

        for item_data in initial_items:
            res_item = await db.execute(select(Item).where(Item.sku == item_data["sku"]))
            if not res_item.scalar_one_or_none():
                db.add(Item(**item_data))
                print(f"[Seed] Item inserido: {item_data['display_name']} ({item_data['sku']})")

        await db.commit()
        print("[Seed] Processo de seed concluído com sucesso!")


if __name__ == "__main__":
    asyncio.run(seed())
