import hashlib
import hmac
import re
import secrets
from datetime import datetime, timedelta, timezone
from uuid import uuid4

from sqlalchemy import Column, DateTime, String, Table, delete, insert, select, update

from .storage import metadata, states

users = Table("qingji_users", metadata, Column("id", String(40), primary_key=True),
              Column("username", String(64), unique=True, nullable=False),
              Column("password_hash", String(200), nullable=False))
sessions = Table("qingji_sessions", metadata, Column("digest", String(64), primary_key=True),
                 Column("user_id", String(40), nullable=False),
                 Column("expires_at", DateTime, nullable=False))

USERNAME = re.compile(r"^[a-z0-9][a-z0-9_.-]{2,63}$")
ITERATIONS = 600_000


def utcnow():
    return datetime.now(timezone.utc).replace(tzinfo=None)


def password_hash(password, salt):
    return hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, ITERATIONS).hex()


def encode_password(password):
    if not 12 <= len(password) <= 128:
        raise ValueError("Password must contain 12 to 128 characters")
    salt = secrets.token_bytes(16)
    return salt.hex() + ":" + password_hash(password, salt)


def digest(token):
    return hashlib.sha256(token.encode()).hexdigest()


class Accounts:
    def __init__(self, engine, legacy_owner):
        self.engine, self.legacy_owner = engine, legacy_owner
        self.dummy = encode_password(secrets.token_urlsafe(32))

    def create(self, username, password, adopt_legacy=False):
        if not USERNAME.fullmatch(username):
            raise ValueError("Username must be 3–64 characters: a-z, 0-9, dot, underscore or hyphen")
        owner = self.legacy_owner if adopt_legacy else uuid4().hex
        encoded = encode_password(password)
        with self.engine.begin() as conn:
            conn.execute(insert(users).values(id=owner, username=username, password_hash=encoded))
            if not adopt_legacy:
                conn.execute(insert(states).values(owner=owner, revision=0))

    def reset_password(self, username, password):
        encoded = encode_password(password)
        with self.engine.begin() as conn:
            owner = conn.execute(select(users.c.id).where(users.c.username == username).with_for_update()).scalar_one_or_none()
            if owner is None:
                raise ValueError("Account not found")
            conn.execute(update(users).where(users.c.id == owner).values(password_hash=encoded))
            conn.execute(delete(sessions).where(sessions.c.user_id == owner))

    def login(self, username, password):
        with self.engine.connect() as conn:
            account = conn.execute(select(users).where(users.c.username == username)).mappings().one_or_none()
        encoded = account["password_hash"] if account is not None else self.dummy
        salt, expected = encoded.split(":")
        correct = hmac.compare_digest(password_hash(password, bytes.fromhex(salt)), expected)
        if not correct or account is None:
            return None
        token = secrets.token_urlsafe(32)
        now = utcnow()
        with self.engine.begin() as conn:
            current_hash = conn.execute(select(users.c.password_hash).where(users.c.id == account["id"]).with_for_update()).scalar_one_or_none()
            if current_hash != encoded:
                return None
            conn.execute(delete(sessions).where(sessions.c.user_id == account["id"], sessions.c.expires_at <= now))
            conn.execute(insert(sessions).values(digest=digest(token), user_id=account["id"], expires_at=now + timedelta(days=30)))
        return {"token": token, "accountId": account["id"], "username": account["username"],
                "legacyOwner": account["id"] == self.legacy_owner}

    def resolve(self, token):
        with self.engine.connect() as conn:
            return conn.execute(select(sessions.c.user_id).where(
                sessions.c.digest == digest(token), sessions.c.expires_at > utcnow())).scalar_one_or_none()

    def logout(self, token):
        with self.engine.begin() as conn:
            conn.execute(delete(sessions).where(sessions.c.digest == digest(token)))
