from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles

from app.api.routes import router
from app.config import settings
from app.dwg.converter import is_oda_available


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    settings.upload_dir.mkdir(parents=True, exist_ok=True)
    if not is_oda_available():
        print("WARNING: ODA File Converter not found. Only DXF uploads will work.")
        print("Install from: https://www.opendesign.com/guestfiles/oda_file_converter")
    yield
    # Shutdown (cleanup could go here)


app = FastAPI(
    title="Interior-Pro",
    description="DWG/DXF to SketchUp Ruby script converter",
    version="0.1.0",
    lifespan=lifespan,
)

app.include_router(router)

static_dir = Path(__file__).parent.parent / "static"
if static_dir.exists():
    app.mount("/", StaticFiles(directory=str(static_dir), html=True), name="static")
