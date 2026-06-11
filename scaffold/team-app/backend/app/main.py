import os
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from prometheus_fastapi_instrumentator import Instrumentator
from pydantic import BaseModel
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine
from sqlalchemy.orm import sessionmaker

DATABASE_URL = os.environ.get(
    "DATABASE_URL",
    "postgresql+asyncpg://webapp:webapp@localhost:5432/webapp",
)

engine = create_async_engine(DATABASE_URL, echo=False)
AsyncSessionLocal = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)


@asynccontextmanager
async def lifespan(app: FastAPI):
    async with engine.begin() as conn:
        await conn.execute(text(
            "CREATE TABLE IF NOT EXISTS items (id SERIAL PRIMARY KEY, title TEXT NOT NULL)"
        ))
    yield
    await engine.dispose()


app = FastAPI(title="Webapp API", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# Expose /metrics for Prometheus scraping
Instrumentator().instrument(app).expose(app)


class ItemIn(BaseModel):
    title: str


class Item(BaseModel):
    id: int
    title: str


@app.get("/health")
async def health():
    return {"status": "ok"}


@app.get("/items", response_model=list[Item])
async def list_items():
    async with AsyncSessionLocal() as session:
        result = await session.execute(text("SELECT id, title FROM items ORDER BY id"))
        return [{"id": row.id, "title": row.title} for row in result]


@app.post("/items", response_model=Item, status_code=201)
async def create_item(item: ItemIn):
    async with AsyncSessionLocal() as session:
        result = await session.execute(
            text("INSERT INTO items (title) VALUES (:title) RETURNING id, title"),
            {"title": item.title},
        )
        await session.commit()
        row = result.first()
        return {"id": row.id, "title": row.title}


@app.delete("/items/{item_id}", status_code=204)
async def delete_item(item_id: int):
    async with AsyncSessionLocal() as session:
        result = await session.execute(
            text("DELETE FROM items WHERE id = :id"), {"id": item_id}
        )
        await session.commit()
        if result.rowcount == 0:
            raise HTTPException(status_code=404, detail="Item not found")
