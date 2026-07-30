import os
from pathlib import Path

HOST = "0.0.0.0"
PORT = 8787

IA_DIR = Path(os.environ.get("IA_DIR", r"C:\Users\seshu\Pictures\insta-automate"))
CONFIG_PATH = IA_DIR / "config.env"

AGENT_DATA_DIR = Path(os.environ["LOCALAPPDATA"]) / "ia-agent"
TOKEN_PATH = AGENT_DATA_DIR / "token"
