import asyncio
import base64
import hashlib
import json
import os
from uuid import uuid4

import httpx
import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine

from qingji.app import create_app
from qingji.config import Settings

TOKEN = "test-token-only-" + "a" * 32
HEADERS = {"Authorization": f"Bearer {TOKEN}"}
PROFILE = {"sex": "male", "age": 30, "heightCM": 175, "weightKG": 70}
AI_RESULT = {"estimatedKcal": 1700, "summary": "根据个人资料估算", "assumptions": ["没有体成分实测"]}
PHOTO = b"\xff\xd8\xff" + b"example-jpeg-header-fixture"
PHOTO_HASH = hashlib.sha256(PHOTO).hexdigest()


def reply(result, reason="stop"):
    return httpx.Response(200, json={"choices": [{"finish_reason": reason, "message": {
        "content": json.dumps(result, ensure_ascii=False), "reasoning_content": "PRIVATE_REASONING"
    }}]})


@pytest.fixture
def fixture(tmp_path):
    def create(provider=None, **kwargs):
        settings = Settings(app_access_token=TOKEN, deepseek_api_key="fake-key", photo_directory=tmp_path / "photos",
                            owner_id=uuid4().hex, **kwargs)
        engine = create_engine(os.getenv("QINGJI_TEST_MYSQL_URL") or f"sqlite:///{tmp_path / 'test.db'}", hide_parameters=True)
        app = create_app(settings, engine, httpx.MockTransport(provider or (lambda _: reply(AI_RESULT))))
        return TestClient(app, headers=HEADERS), app
    return create


def test_deepseek_sse_contract(fixture):
    def model(request):
        assert request.url.path == "/chat/completions"
        data = json.loads(request.content)
        assert data["model"] == "deepseek-flash"
        assert json.loads(data["messages"][1]["content"]) == PROFILE
        assert data["response_format"] == {"type": "json_object"}
        return reply(AI_RESULT)
    client, _ = fixture(model)
    with client:
        response = client.post("/v1/analyze/metabolism", json=PROFILE)
    assert response.headers["content-type"].startswith("text/event-stream")
    assert [line for line in response.text.splitlines() if line.startswith("event:")] == [
        "event: progress", "event: progress", "event: progress", "event: result"]
    assert "PRIVATE_REASONING" not in response.text
    assert "1700" in response.text


def test_multimodal_photo_and_no_food(fixture):
    def model(request):
        message = json.loads(request.content)["messages"][1]["content"]
        assert message[1]["image_url"]["url"] == "data:image/jpeg;base64," + base64.b64encode(PHOTO).decode()
        return reply({"isFood": False, "items": [], "summary": "没有可辨认食物", "assumptions": [], "questions": []})
    client, _ = fixture(model)
    with client:
        result = client.post("/v1/analyze/meal", json={"imageBase64": base64.b64encode(PHOTO).decode()})
        assert "NO_FOOD" in result.text
        assert client.post("/v1/analyze/meal", json={"imageBase64": "x" * 20}).status_code == 400


@pytest.mark.parametrize("result,reason", [({}, "stop"), (AI_RESULT, "length"), ({**AI_RESULT, "estimatedKcal": -1}, "stop")])
def test_invalid_model_result_is_not_returned(fixture, result, reason):
    client, _ = fixture(lambda _: reply(result, reason))
    with client:
        response = client.post("/v1/analyze/metabolism", json=PROFILE)
    assert "INVALID_AI_RESULT" in response.text
    assert "event: result" not in response.text


def test_timeout_releases_concurrency_slot(fixture):
    async def slow(_):
        await asyncio.sleep(1)
        return reply(AI_RESULT)
    client, app = fixture(slow, request_timeout_seconds=0.03, max_concurrent_requests=1)
    with client:
        assert "TIMEOUT" in client.post("/v1/analyze/metabolism", json=PROFILE).text
        assert app.state.active == 0
        assert "TIMEOUT" in client.post("/v1/analyze/metabolism", json=PROFILE).text


def example():
    meal_id, food_id = str(uuid4()), str(uuid4())
    filename = meal_id.upper() + ".jpg"
    snapshot = {"profile": {**PROFILE, "dailyTarget": 1800}, "aiConsent": True,
                "metabolism": {"response": AI_RESULT, "profileFingerprint": "male|30|175.0|70.0", "createdAt": 815000000},
                "meals": [{"id": meal_id, "consumedAt": 815000000, "kind": "lunch", "source": "ai",
                           "items": [{"id": food_id, "name": "米饭🍚", "grams": 150, "kcal": 174}],
                           "createdAt": 815000000, "photoFilename": filename}],
                "activityDays": [{"id": "2026-11-08|Asia/Shanghai", "day": "2026-11-08", "timeZone": "Asia/Shanghai",
                                  "activeKcal": 380, "updatedAt": 815000000}]}
    return {"expectedRevision": 0, "snapshot": snapshot, "photos": [{"filename": filename, "sha256": PHOTO_HASH}]}


def test_restart_restore_and_protected_photos(fixture):
    client, app = fixture()
    payload = example()
    with client:
        assert client.get("/healthz", headers={"Authorization": ""}).status_code == 200
        assert client.get("/v1/backup", headers={"Authorization": ""}).status_code == 401
        assert client.get(f"/v1/photos/{PHOTO_HASH}", headers={"Authorization": ""}).status_code == 401
        assert client.get("/v1/backup").json()["snapshot"] is None
        assert client.put("/v1/backup", json=payload).json()["code"] == "MISSING_PHOTO"
        assert client.put("/v1/photos/" + "0" * 64, content=PHOTO).json()["code"] == "HASH_MISMATCH"
        for _ in range(2):
            assert client.put(f"/v1/photos/{PHOTO_HASH}", content=PHOTO).status_code == 200
        assert client.put("/v1/backup", json=payload).json()["revision"] == 1
    with TestClient(app, headers=HEADERS) as new_phone:
        remote = new_phone.get("/v1/backup").json()
        assert remote["revision"] == 1
        assert remote["snapshot"]["aiConsent"] is False
        assert remote["snapshot"]["profile"]["dailyTarget"] == 1800
        assert remote["snapshot"]["meals"][0]["items"][0]["name"] == "米饭🍚"
        assert remote["snapshot"]["metabolism"]["response"] == AI_RESULT
        assert remote["snapshot"]["activityDays"][0]["activeKcal"] == 380
        assert remote["photos"] == payload["photos"]
        assert new_phone.get(f"/v1/photos/{PHOTO_HASH}").content == PHOTO
        assert new_phone.put("/v1/backup", json=payload).status_code == 409
        assert new_phone.get("/v1/backup").json() == remote
        payload.update(expectedRevision=1, photos=[])
        payload["snapshot"]["meals"] = []
        assert new_phone.put("/v1/backup", json=payload).json()["revision"] == 2
        assert new_phone.get("/v1/backup").json()["snapshot"]["meals"] == []


def test_no_model_key_does_not_block_backup(fixture):
    client, app = fixture()
    settings = Settings(app_access_token=TOKEN, photo_directory=app.state.storage.directory.parent, owner_id=uuid4().hex,
                        _env_file=None, deepseek_api_key="")
    no_ai = create_app(settings, app.state.storage.engine)
    with TestClient(no_ai, headers=HEADERS) as client:
        assert client.get("/v1/backup").status_code == 200
        assert client.post("/v1/analyze/metabolism", json=PROFILE).json()["code"] == "AI_NOT_CONFIGURED"
