from pathlib import Path
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    oda_converter_path: str = ""
    libredwg_path: str = ""
    upload_dir: Path = Path("./uploads")
    default_wall_height: float = 2700.0
    default_wall_thickness: float = 150.0

    model_config = {"env_file": ".env", "env_file_encoding": "utf-8"}


settings = Settings()
