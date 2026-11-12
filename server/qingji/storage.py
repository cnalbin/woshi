"""Transactional, revisioned single-owner backups and content-addressed private photos."""
import hashlib
import os
from datetime import datetime, timezone
from pathlib import Path
from uuid import uuid4

from sqlalchemy import JSON, BigInteger, Column, DateTime, Integer, MetaData, String, Table, delete, insert, select, update
from sqlalchemy.engine import Engine
from sqlalchemy.exc import IntegrityError

from .schemas import BackupWrite

metadata = MetaData()
states = Table("qingji_sync_state", metadata,
               Column("owner", String(40), primary_key=True),
               Column("revision", BigInteger, nullable=False), Column("updated_at", DateTime, nullable=True))
documents = Table("qingji_documents", metadata,
                  Column("owner", String(40), primary_key=True), Column("record_id", String(180), primary_key=True),
                  Column("kind", String(20), nullable=False), Column("payload", JSON, nullable=False))
photos = Table("qingji_photos", metadata,
               Column("owner", String(40), primary_key=True), Column("sha256", String(64), primary_key=True),
               Column("mime", String(30), nullable=False), Column("size", Integer, nullable=False),
               Column("created_at", DateTime, nullable=False))
manifest = Table("qingji_photo_refs", metadata,
                 Column("owner", String(40), primary_key=True), Column("filename", String(64), primary_key=True),
                 Column("sha256", String(64), nullable=False))


class StorageError(Exception):
    def __init__(self, status: int, code: str, message: str):
        self.status, self.code, self.message = status, code, message


def image_mime(data: bytes) -> str:
    if not 16 <= len(data) <= 4_000_000:
        raise StorageError(400, "INVALID_PHOTO", "照片大小不符合要求，最多 4 MB。")
    if data.startswith(b"\xff\xd8\xff"):
        return "image/jpeg"
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png"
    raise StorageError(400, "INVALID_PHOTO", "仅支持 JPEG 或 PNG 图片。")


class Storage:
    def __init__(self, engine: Engine, directory: Path, owner: str = "owner"):
        self.engine, self.owner = engine, owner
        self.directory = directory.resolve() / owner
        self.directory.mkdir(parents=True, exist_ok=True)

    def initialize(self) -> None:
        # Creates only namespaced application tables; never creates/drops an existing NAS database.
        metadata.create_all(self.engine)
        try:
            with self.engine.begin() as conn:
                if conn.execute(select(states.c.owner).where(states.c.owner == self.owner)).first() is None:
                    conn.execute(insert(states).values(owner=self.owner, revision=0))
        except IntegrityError:
            pass  # Another worker initialized the same owner first.

    def read(self) -> dict:
        with self.engine.begin() as conn:
            state = conn.execute(select(states).where(states.c.owner == self.owner).with_for_update(read=True)).mappings().one()
            rows = conn.execute(select(documents).where(documents.c.owner == self.owner)).mappings().all()
            refs = conn.execute(select(manifest).where(manifest.c.owner == self.owner)).mappings().all()
            snapshot = None
            if state["revision"]:
                snapshot = {"schemaVersion": 1, "profile": None, "metabolism": None,
                            "meals": [], "activityDays": [], "healthMetrics": [], "aiConsent": False}
                for row in rows:
                    if row["kind"] in ("profile", "metabolism"):
                        snapshot[row["kind"]] = row["payload"]
                    elif row["kind"] == "meal":
                        snapshot["meals"].append(row["payload"])
                    elif row["kind"] == "activity":
                        snapshot["activityDays"].append(row["payload"])
                    elif row["kind"] == "health":
                        snapshot["healthMetrics"].append(row["payload"])
            stamp = state["updated_at"]
            return {"revision": state["revision"], "updatedAt": stamp.replace(tzinfo=timezone.utc).isoformat() if stamp else None,
                    "snapshot": snapshot, "photos": [{"filename": r["filename"], "sha256": r["sha256"]} for r in refs
                                                      if (self.directory / r["sha256"]).is_file()]}

    def revision(self) -> int:
        with self.engine.connect() as conn:
            return conn.execute(select(states.c.revision).where(states.c.owner == self.owner)).scalar_one()

    def write(self, backup: BackupWrite) -> dict:
        body = backup.snapshot.model_dump(mode="json")
        rows = [{"owner": self.owner, "record_id": "profile", "kind": "profile", "payload": body["profile"]}]
        if body["metabolism"] is not None:
            rows.append({"owner": self.owner, "record_id": "metabolism", "kind": "metabolism", "payload": body["metabolism"]})
        for key, kind in [("meals", "meal"), ("activityDays", "activity")]:
            rows.extend({"owner": self.owner, "record_id": f"{kind}:{item['id']}", "kind": kind, "payload": item} for item in body[key])
        if body["healthMetrics"] is not None:
            rows.extend({"owner": self.owner, "record_id": f"health:{item['id']}", "kind": "health", "payload": item} for item in body["healthMetrics"])
        with self.engine.begin() as conn:
            state = conn.execute(select(states).where(states.c.owner == self.owner).with_for_update()).mappings().one()
            if state["revision"] != backup.expectedRevision:
                raise StorageError(409, "REVISION_CONFLICT", "NAS 已有更新版本，本机记录已保留。请先检查并恢复 NAS 数据。")
            wanted = {p.sha256 for p in backup.photos}
            if wanted:
                existing = set(conn.execute(select(photos.c.sha256).where(photos.c.owner == self.owner, photos.c.sha256.in_(wanted))).scalars())
                if wanted != existing or any(not (self.directory / digest).is_file() for digest in wanted):
                    raise StorageError(422, "MISSING_PHOTO", "部分照片尚未上传，备份未提交，请重试。")
            deletion = delete(documents).where(documents.c.owner == self.owner)
            if body["healthMetrics"] is None:
                deletion = deletion.where(documents.c.kind != "health")
            conn.execute(deletion)
            conn.execute(delete(manifest).where(manifest.c.owner == self.owner))
            conn.execute(insert(documents), rows)
            if backup.photos:
                conn.execute(insert(manifest), [{"owner": self.owner, **p.model_dump()} for p in backup.photos])
            now = datetime.now(timezone.utc).replace(tzinfo=None)
            revision = state["revision"] + 1
            conn.execute(update(states).where(states.c.owner == self.owner).values(revision=revision, updated_at=now))
        return {"revision": revision, "updatedAt": now.replace(tzinfo=timezone.utc).isoformat()}

    def put_photo(self, digest: str, data: bytes) -> None:
        mime = image_mime(data)
        if hashlib.sha256(data).hexdigest() != digest:
            raise StorageError(400, "HASH_MISMATCH", "照片校验失败，请重新上传。")
        destination = self.directory / digest
        temporary = self.directory / f".upload-{uuid4()}"
        try:
            with temporary.open("xb") as stream:
                stream.write(data)
                stream.flush()
                os.fsync(stream.fileno())
            os.replace(temporary, destination)
            try:
                with self.engine.begin() as conn:
                    if conn.execute(select(photos.c.sha256).where(photos.c.owner == self.owner, photos.c.sha256 == digest)).first() is None:
                        conn.execute(insert(photos).values(owner=self.owner, sha256=digest, mime=mime,
                                                          size=len(data), created_at=datetime.now(timezone.utc).replace(tzinfo=None)))
            except IntegrityError:
                pass  # Content-addressed retry is idempotent.
        finally:
            temporary.unlink(missing_ok=True)

    def get_photo(self, digest: str) -> tuple[Path, str]:
        with self.engine.connect() as conn:
            row = conn.execute(select(photos.c.mime).where(photos.c.owner == self.owner, photos.c.sha256 == digest)).first()
        path = self.directory / digest
        if row is None or not path.is_file():
            raise StorageError(404, "PHOTO_NOT_FOUND", "NAS 中找不到这张照片，请检查照片目录挂载和备份。")
        return path, row[0]
