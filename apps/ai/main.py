from fastapi import FastAPI
from ocr_service import router as ocr_router

app = FastAPI(title="SobatNira AI")
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
