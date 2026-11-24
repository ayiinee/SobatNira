from contextlib import asynccontextmanager

from fastapi import FastAPI
from ocr_service import router as ocr_router
from ocr_service import validate_runtime, PADDLE_WORKER


@asynccontextmanager
async def lifespan(_app):
    validate_runtime()
    try:
        yield
    finally:
        PADDLE_WORKER.close()


app = FastAPI(title="SobatNira AI", lifespan=lifespan)
app.include_router(ocr_router)


@app.get("/health")
def health():
    return {"status": "ok", "service": "sobatnira-ai"}


@app.get("/demo/draft")
def demo_draft():
    return {
        "synthetic": True,
        "lotCode": "DEMO-261114-01",
        "stage": "Penerimaan Tebu",
        "supplier": "Pemasok Demo",
        "netWeightKg": 1250,
    }
