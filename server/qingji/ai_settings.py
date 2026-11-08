"""Account-scoped provider settings with encrypted keys and restricted destinations."""
import os
from urllib.parse import urlsplit

from cryptography.fernet import Fernet
from sqlalchemy import Column, JSON, String, Table, insert, select, update

from .storage import StorageError, metadata, states

configurations = Table("qingji_ai_settings", metadata,
                       Column("owner", String(40), primary_key=True),
                       Column("payload", JSON, nullable=False))


class ProviderSettings:
    def __init__(self, engine, settings):
        self.engine, self.settings = engine, settings

    def cipher(self):
        directory = self.settings.photo_directory
        directory.mkdir(parents=True, exist_ok=True)
        path = directory / ".ai-encryption-key"
        # A separate lock makes concurrent worker startup safe.
        from filelock import FileLock
        with FileLock(str(directory / ".ai-key.lock")):
            if not path.exists():
                with path.open("xb") as stream:
                    os.chmod(path, 0o600)
                    stream.write(Fernet.generate_key())
                    stream.flush()
                    os.fsync(stream.fileno())
            return Fernet(path.read_bytes())

    def read(self, owner):
        with self.engine.connect() as conn:
            value = conn.execute(select(configurations.c.payload).where(configurations.c.owner == owner)).scalar_one_or_none()
        return value

    def save(self, owner, value):
        parsed = urlsplit(value.baseURL)
        allowed = self.settings.ai_allowed_hosts.split(",")
        if (parsed.scheme != "https" or parsed.hostname not in allowed or parsed.port not in (None, 443)
                or parsed.username or parsed.password or parsed.query or parsed.fragment):
            raise StorageError(400, "INVALID_PROVIDER", "模型地址需使用管理员允许的 HTTPS 域名。")
        with self.engine.begin() as conn:
            conn.execute(select(states.c.owner).where(states.c.owner == owner).with_for_update()).one()
            old = conn.execute(select(configurations.c.payload).where(configurations.c.owner == owner)).scalar_one_or_none()
            key = value.apiKey.get_secret_value()
            if old and not key and old["baseURL"] != value.baseURL.rstrip("/"):
                raise StorageError(400, "KEY_REQUIRED", "更换服务地址时请重新填写 API Key。")
            encrypted = self.cipher().encrypt(key.encode()).decode() if key else (old or {}).get("encryptedKey", "")
            payload = {"baseURL": value.baseURL.rstrip("/"), "textModel": value.textModel,
                       "visionModel": value.visionModel, "encryptedKey": encrypted}
            if old is None:
                conn.execute(insert(configurations).values(owner=owner, payload=payload))
            else:
                conn.execute(update(configurations).where(configurations.c.owner == owner).values(payload=payload))

    def public(self, owner):
        value = self.read(owner) or {}
        return {"baseURL": value.get("baseURL", "https://api.deepseek.com"),
                "textModel": value.get("textModel", ""), "visionModel": value.get("visionModel", ""),
                "hasKey": bool(value.get("encryptedKey"))}

    def credentials(self, owner, kind):
        value = self.read(owner)
        if value:
            key = value.get("encryptedKey", "")
            model = value["visionModel" if kind == "meal" else "textModel"]
            if not key or not model:
                raise StorageError(400, "AI_NOT_CONFIGURED", "请先填写 API Key 和本次分析使用的模型名称。")
            return value["baseURL"], self.cipher().decrypt(key.encode()).decode(), model
        key = self.settings.deepseek_api_key.get_secret_value()
        if not key or key.startswith("replace-"):
            raise StorageError(503, "AI_NOT_CONFIGURED", "请在“我的 → AI 模型设置”配置模型。")
        return (self.settings.deepseek_base_url, key,
                self.settings.deepseek_vision_model if kind == "meal" else self.settings.deepseek_text_model)
