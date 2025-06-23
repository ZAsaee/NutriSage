from pathlib import Path
from dotenv import load_dotenv


def load_env():
    """
    Load .env from the repo root (one directory above nutrisage_cdk).
    Does nothing if the file doesn’t exist.
    """
    env_path = Path(__file__).resolve().parent.parent / ".env"
    if env_path.exists():
        load_dotenv(dotenv_path=env_path, override=False)
