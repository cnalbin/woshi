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
from qingji.schemas import BackupWrite

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
    def create(provider=None, enable_legacy_token=True, **kwargs):
        settings = Settings(app_access_token=TOKEN, enable_legacy_token=enable_legacy_token,
                            deepseek_api_key="fake-key", photo_directory=tmp_path / "photos",
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
    settings = Settings(app_access_token=TOKEN, enable_legacy_token=True,
                        photo_directory=app.state.storage.directory.parent, owner_id=uuid4().hex,
                        _env_file=None, deepseek_api_key="")
    no_ai = create_app(settings, app.state.storage.engine)
    with TestClient(no_ai, headers=HEADERS) as client:
        assert client.get("/v1/backup").status_code == 200
        assert client.post("/v1/analyze/metabolism", json=PROFILE).json()["code"] == "AI_NOT_CONFIGURED"


def test_account_isolation_and_session_revocation(fixture):
    client, app = fixture(enable_legacy_token=False)
    password = "test-password-only"
    with client:
        app.state.accounts.create("alice", password)
        app.state.accounts.create("bob", password)
        assert client.get("/v1/backup").status_code == 401
        assert client.post("/v1/auth/login", json={"username": "alice", "password": "wrong"}).status_code == 401

        def login(name, secret=password):
            response = client.post("/v1/auth/login", json={"username": name, "password": secret})
            assert response.status_code == 200
            return {"Authorization": "Bearer " + response.json()["token"]}

        alice, bob = login("ALICE"), login("bob")
        payload = example()
        photo_url = f"/v1/photos/{PHOTO_HASH}"
        assert client.put(photo_url, content=PHOTO, headers=alice).status_code == 200
        assert client.put("/v1/backup", json=payload, headers=alice).json()["revision"] == 1
        assert client.get(photo_url, headers=alice).content == PHOTO
        assert client.get(photo_url, headers=bob).status_code == 404
        assert client.get("/v1/backup", headers=bob).json()["revision"] == 0
        assert client.put("/v1/backup", json=payload, headers=bob).json()["code"] == "MISSING_PHOTO"
        payload["snapshot"]["profile"]["dailyTarget"] = 2200
        payload["snapshot"]["meals"] = []
        payload["photos"] = []
        assert client.put("/v1/backup", json=payload, headers=bob).json()["revision"] == 1
        assert client.get("/v1/backup", headers=alice).json()["snapshot"]["profile"]["dailyTarget"] == 1800
        assert client.get("/v1/backup", headers=bob).json()["snapshot"]["profile"]["dailyTarget"] == 2200
        assert client.post("/v1/auth/logout", headers=alice).status_code == 204
        assert client.get("/v1/backup", headers=alice).status_code == 401
        assert client.get("/v1/backup", headers=bob).status_code == 200
        app.state.accounts.reset_password("bob", "updated-test-password")
        assert client.get("/v1/backup", headers=bob).status_code == 401
        assert client.get("/v1/backup", headers=login("bob", "updated-test-password")).json()["revision"] == 1


def test_existing_backup_belongs_only_to_designated_account(fixture):
    client, app = fixture(enable_legacy_token=False)
    payload = example()
    with client:
        app.state.storage.put_photo(PHOTO_HASH, PHOTO)
        app.state.storage.write(BackupWrite.model_validate(payload))
        app.state.accounts.create("existing", "test-password-only", adopt_legacy=True)
        app.state.accounts.create("newuser", "test-password-only")
        for name, revision, legacy in [("existing", 1, True), ("newuser", 0, False)]:
            result = client.post("/v1/auth/login", json={"username": name, "password": "test-password-only"}).json()
            assert result["legacyOwner"] is legacy
            headers = {"Authorization": f"Bearer {result['token']}"}
            assert client.get("/v1/backup", headers=headers).json()["revision"] == revision
            assert client.get(f"/v1/photos/{PHOTO_HASH}", headers=headers).status_code == (200 if legacy else 404)


def test_registration_and_private_ai_settings(fixture):
    seen = []
    def provider(request):
        seen.append(json.loads(request.content)["model"])
        assert request.headers["Authorization"] == "Bearer personal-test-key"
        return reply(AI_RESULT)
    client, _ = fixture(provider, enable_legacy_token=False)
    with client:
        credentials = {"username": "newaccount", "password": "test-password-only"}
        result = client.post("/v1/auth/register", json=credentials)
        assert result.status_code == 200
        headers = {"Authorization": "Bearer " + result.json()["token"]}
        assert client.post("/v1/auth/register", json=credentials).status_code == 409
        payload = {"baseURL": "https://api.deepseek.com", "apiKey": "personal-test-key",
                   "textModel": "my-text-model", "visionModel": "my-vision-model"}
        assert client.put("/v1/ai/settings", json=payload, headers=headers).status_code == 200
        public = client.get("/v1/ai/settings", headers=headers)
        assert "personal-test-key" not in public.text
        assert public.json()["hasKey"]
        assert client.post("/v1/ai/test", headers=headers).status_code == 200
        assert seen == ["my-text-model"]
        payload["baseURL"] = "https://127.0.0.1"
        assert client.put("/v1/ai/settings", json=payload, headers=headers).status_code == 400
        other = client.post("/v1/auth/register", json={**credentials, "username": "another"}).json()
        other_headers = {"Authorization": "Bearer " + other["token"]}
        assert not client.get("/v1/ai/settings", headers=other_headers).json()["hasKey"]


def test_prompt_drafts_debug_and_private_balance(fixture):
    calls = []

    def provider(request):
        payload = json.loads(request.content) if request.method == "POST" else None
        calls.append((request.url, request.headers["Authorization"], payload))
        if request.url.path == "/user/balance":
            return httpx.Response(200, json={"is_available": True, "balance_infos": [
                {"currency": "CNY", "total_balance": "12.50", "granted_balance": "2.50", "topped_up_balance": "10.00"}
            ], "private_field": "hidden"})
        if payload.get("response_format"):
            return reply(AI_RESULT)
        return httpx.Response(200, json={"choices": [{"finish_reason": "stop", "message": {"content": "照片调试完成"}}],
                                         "usage": {"total_tokens": 21}})

    client, _ = fixture(provider, enable_legacy_token=False)
    with client:
        def register(name):
            value = client.post("/v1/auth/register", json={"username": name, "password": "test-password-only"}).json()
            return {"Authorization": "Bearer " + value["token"]}

        owner, other = register("prompt-owner"), register("prompt-other")
        settings = {"baseURL": "https://api.deepseek.com/v1", "apiKey": "owner-private-key",
                    "textModel": "text", "visionModel": "vision", "mealPrompt": "区分精制米饭和糙米。",
                    "metabolismPrompt": "明确说明使用的估算方法。"}
        assert client.put("/v1/ai/settings", headers=owner, json=settings).status_code == 200
        assert client.put("/v1/ai/settings", headers=owner, json={
            "baseURL": settings["baseURL"], "textModel": "text", "visionModel": "vision"
        }).json()["mealPrompt"] == settings["mealPrompt"]
        assert client.get("/v1/ai/settings", headers=other).json()["metabolismPrompt"] == ""
        assert client.post("/v1/ai/test", headers=owner).status_code == 200
        assert settings["metabolismPrompt"] in calls[-1][2]["messages"][0]["content"]
        assert '"estimatedKcal"' in calls[-1][2]["messages"][0]["content"]

        draft = {**settings, "apiKey": "temporary-key", "visionModel": "draft-vision"}
        debug = {"configuration": draft, "mode": "free", "prompt": "列出颜色", "text": "检查照片",
                 "imageBase64": base64.b64encode(PHOTO).decode()}
        result = client.post("/v1/ai/debug", headers=owner, json=debug)
        assert result.status_code == 200
        assert result.json()["output"] == "照片调试完成"
        assert result.json()["usage"]["total_tokens"] == 21
        assert calls[-1][1] == "Bearer temporary-key"
        assert calls[-1][2]["model"] == "draft-vision"
        assert calls[-1][2]["messages"][0]["content"] == "列出颜色"
        assert calls[-1][2]["messages"][1]["content"][1]["type"] == "image_url"
        assert client.get("/v1/ai/settings", headers=owner).json()["visionModel"] == "vision"
        structured = client.post("/v1/ai/debug", headers=owner,
                                 json={**debug, "mode": "meal", "prompt": settings["mealPrompt"]})
        assert structured.json()["formatValid"] is False
        assert settings["mealPrompt"] in calls[-1][2]["messages"][0]["content"]

        balance = client.post("/v1/ai/balance", headers=owner, json={**settings, "apiKey": ""})
        assert balance.json() == {"supported": True, "is_available": True, "balance_infos": [
            {"currency": "CNY", "total_balance": "12.50", "granted_balance": "2.50", "topped_up_balance": "10.00"}
        ]}
        assert str(calls[-1][0]) == "https://api.deepseek.com/user/balance"
        assert calls[-1][1] == "Bearer owner-private-key"
        count = len(calls)
        assert client.post("/v1/ai/balance", headers=other, json={**settings, "apiKey": ""}).status_code == 400
        assert client.post("/v1/ai/balance", headers=owner, json={**settings, "baseURL": "https://api.openai.com/v1"}).json()["supported"] is False
        assert client.post("/v1/ai/debug", headers=owner,
                           json={**debug, "configuration": {**draft, "baseURL": "https://127.0.0.1"}}).status_code == 400
        assert len(calls) == count
        assert client.put("/v1/ai/settings", headers=owner, json={**settings, "mealPrompt": ""}).json()["mealPrompt"] == ""
