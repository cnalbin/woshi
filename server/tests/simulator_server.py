"""Launch the real API with a disposable database and fake DeepSeek response in CI."""
import asyncio
import json
import os
from pathlib import Path
from tempfile import TemporaryDirectory

import httpx
import uvicorn
from sqlalchemy import create_engine

from qingji.app import create_app
from qingji.config import Settings


async def fake_model(_):
    await asyncio.sleep(2.5)
    result = {"estimatedKcal": 1700, "summary": "UI 集成测试：已通过真实 SSE 接收代谢结果。",
              "assumptions": ["测试模拟值"]}
    return httpx.Response(200, json={"choices": [{"finish_reason": "stop", "message": {"content": json.dumps(result)}}]})


if __name__ == "__main__":
    if os.environ.get("QINGJI_CI_MOCK") != "1":
        raise SystemExit("Simulator fixture only")
    with TemporaryDirectory() as folder:
        settings = Settings(app_access_token="ci-only-token-abcdefghijklmnopqrstuvwxyz", deepseek_api_key="fake-key",
                            photo_directory=Path(folder) / "photos", _env_file=None)
        api = create_app(settings, create_engine(f"sqlite:///{folder}/test.db"), httpx.MockTransport(fake_model))
        uvicorn.run(api, host="127.0.0.1", port=8787, access_log=False)
