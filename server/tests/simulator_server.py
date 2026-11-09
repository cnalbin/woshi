"""Launch the real API with a disposable database and fake DeepSeek response in CI."""
import asyncio
import json
import os
from datetime import datetime, timedelta, timezone
from uuid import uuid4
from zoneinfo import ZoneInfo
from pathlib import Path
from tempfile import TemporaryDirectory

import httpx
import uvicorn
from sqlalchemy import create_engine

from qingji.app import create_app
from qingji.config import Settings
from qingji.schemas import BackupWrite
from qingji.storage import Storage


async def fake_model(request):
    content = json.loads(request.content)["messages"][-1]["content"]
    await asyncio.sleep(5 if isinstance(content, list) else 2.5)
    if isinstance(content, list):
        result = {"isFood": True, "items": [
            {"name": "米饭", "estimatedGrams": 150.0, "estimatedKcal": 174.0},
            {"name": "宫保鸡丁", "estimatedGrams": 250.0, "estimatedKcal": 560.0},
            {"name": "炒青菜", "estimatedGrams": 150.0, "estimatedKcal": 166.0}],
            "summary": "UI 测试模拟食物结果，等待用户核对。", "assumptions": ["按整份估算，用油量待确认"], "questions": ["实际吃下了多少？"]}
    else:
        result = {"estimatedKcal": 1700, "summary": "UI 集成测试：已通过真实 SSE 接收代谢结果。",
                  "assumptions": ["测试模拟值"]}
    return httpx.Response(200, json={"choices": [{"finish_reason": "stop", "message": {"content": json.dumps(result)}}]})


if __name__ == "__main__":
    if os.environ.get("QINGJI_CI_MOCK") != "1":
        raise SystemExit("Simulator fixture only")
    with TemporaryDirectory() as folder:
        settings = Settings(deepseek_api_key="fake-key",
                            photo_directory=Path(folder) / "photos", _env_file=None)
        api = create_app(settings, create_engine(f"sqlite:///{folder}/test.db"), httpx.MockTransport(fake_model))
        api.state.storage.initialize()
        for username in ("first-user", "second-user"):
            api.state.accounts.create(username, "test-password-only")
        owner = api.state.accounts.login("first-user", "test-password-only")["accountId"]
        now = datetime.now(timezone.utc)
        meals, days = [], []
        for offset in range(730):
            date = now - timedelta(days=offset, minutes=5)
            stamp = date.timestamp() - 978307200
            for kind in ("breakfast", "lunch", "dinner"):
                meals.append({"id": str(uuid4()), "consumedAt": stamp, "kind": kind,
                    "items": [{"id": str(uuid4()), "name": "历史食物", "kcal": 500.0}],
                    "source": "manual", "createdAt": stamp})
            for zone in ("UTC", "GMT", "America/Los_Angeles", "Asia/Shanghai"):
                key = date.astimezone(ZoneInfo(zone)).strftime("%Y-%m-%d")
                days.append({"id": key + "|" + zone, "day": key, "timeZone": zone,
                    "activeKcal": 350.0, "updatedAt": stamp})
        Storage(api.state.storage.engine, settings.photo_directory, owner).write(BackupWrite.model_validate({
            "expectedRevision": 0, "snapshot": {"schemaVersion": 1,
                "profile": {"sex": "male", "age": 30, "heightCM": 175.0, "weightKG": 70.0, "dailyTarget": 1800.0},
                "meals": meals, "activityDays": days}, "photos": []}))
        uvicorn.run(api, host="127.0.0.1", port=8787, access_log=False)
