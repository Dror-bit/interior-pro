from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles

from app.api.routes import router
from app.config import settings
from app.dwg.converter import get_available_converter


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    settings.upload_dir.mkdir(parents=True, exist_ok=True)
    converter = get_available_converter()
    if converter == "libredwg":
        print("DWG converter: LibreDWG (free, open-source)")
    elif converter == "oda":
        print("DWG converter: ODA File Converter")
    else:
        print("WARNING: No DWG converter found. Only DXF and PDF uploads will work.")
        print("Install LibreDWG: sudo apt install libredwg-tools")
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
