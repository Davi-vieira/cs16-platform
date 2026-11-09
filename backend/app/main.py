import os
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager

from app.api import players, items, wallet, payments, admin, auth, webhooks
from app.models.database import init_db


@asynccontextmanager
async def lifespan(app: FastAPI):
    await init_db()
    yield


app = FastAPI(
    title="Vieira-STRIKE API",
    version="1.0.0",
    docs_url="/api/docs",
    redoc_url=None,
    lifespan=lifespan,
)

cors_env = os.environ.get("CORS_ORIGINS", "http://localhost:3000,http://localhost:8080,https://*.github.io")
allowed_origins = [orig.strip() for orig in cors_env.split(",") if orig.strip()]

app.add_middleware(
    CORSMiddleware,
    allow_origins=allowed_origins if "*" not in allowed_origins else ["*"],
    allow_origin_regex=r"https://.*\.github\.io" if any(".github.io" in o for o in allowed_origins) else None,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router,     prefix="/api/auth",     tags=["auth"])
app.include_router(players.router,  prefix="/api/players",  tags=["players"])
app.include_router(items.router,    prefix="/api/items",    tags=["items"])
app.include_router(wallet.router,   prefix="/api/wallet",   tags=["wallet"])
app.include_router(payments.router, prefix="/api/payments", tags=["payments"])
app.include_router(webhooks.router, prefix="/api/webhooks", tags=["webhooks"])
app.include_router(admin.router,    prefix="/api/admin",    tags=["admin"])


@app.get("/health")
async def health():
    return {"status": "ok"}
