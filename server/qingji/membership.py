"""Account entitlements and durable, transactional analysis quotas."""

from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from uuid import UUID, NAMESPACE_URL, uuid4, uuid5

from sqlalchemy import JSON, Column, DateTime, Index, Integer, String, Table, delete, func, insert, select, update

from .accounts import utcnow, users
from .storage import StorageError, metadata, states


subscriptions = Table(
    "qingji_memberships", metadata,
    Column("owner", String(40), primary_key=True),
    Column("original_id", String(80), nullable=False, unique=True),
    Column("transaction_id", String(80), nullable=False),
    Column("period_start", DateTime, nullable=False),
    Column("period_end", DateTime, nullable=False),
    Column("grace_end", DateTime),
    Column("revoked_at", DateTime),
    Column("signed_at", DateTime, nullable=False),
    Column("renewal", Integer),
)
preferences = Table(
    "qingji_membership_preferences", metadata,
    Column("owner", String(40), primary_key=True),
    Column("model", String(12), nullable=False),
    Column("skin", String(12), nullable=False),
)
usage = Table(
    "qingji_ai_quota", metadata,
    Column("owner", String(40), primary_key=True),
    Column("period", String(80), primary_key=True),
    Column("used", Integer, nullable=False),
)
jobs = Table(
    "qingji_ai_analysis_jobs", metadata,
    Column("owner", String(40), primary_key=True),
    Column("job_id", String(64), primary_key=True),
    Column("period", String(80), nullable=False),
    Column("fingerprint", String(64), nullable=False),
    Column("phase", String(20), nullable=False),
    Column("lease", String(32)),
    Column("answer_hash", String(64)),
    Column("expires_at", DateTime, nullable=False),
    Column("output", JSON),
)
Index("qingji_ai_analysis_owner_expiry", jobs.c.owner, jobs.c.expires_at)
Index("qingji_ai_analysis_expiry", jobs.c.expires_at)


def account_token(owner):
    try:
        return UUID(owner)
    except ValueError:
        return uuid5(NAMESPACE_URL, f"com.cnalbin.qingji:{owner}")


def apple_time(milliseconds):
    return datetime.fromtimestamp(milliseconds / 1000, tz=timezone.utc).replace(tzinfo=None)


@dataclass(frozen=True)
class AnalysisSlot:
    job_id: str
    lease: str | None
    cached: dict | None = None
    refining: bool = False


class Membership:
    limit = 100

    def __init__(self, engine, settings):
        self.engine = engine
        self.settings = settings

    @staticmethod
    def lock_account(conn, owner):
        # Existing account row serializes quota and entitlement writes across workers.
        conn.execute(select(states.c.owner).where(states.c.owner == owner).with_for_update()).one()

    @staticmethod
    def membership(conn, owner, now):
        row = conn.execute(select(subscriptions).where(subscriptions.c.owner == owner)).mappings().first()
        active = bool(row and not row["revoked_at"] and max(row["period_end"], row["grace_end"] or row["period_end"]) > now)
        return row, active

    @staticmethod
    def period(row, active):
        return row["transaction_id"] if active else "trial"

    @staticmethod
    def used(conn, owner, period):
        return conn.execute(select(usage.c.used).where(
            usage.c.owner == owner, usage.c.period == period)).scalar_one_or_none() or 0

    def status(self, owner):
        now = utcnow()
        with self.engine.connect() as conn:
            row, active = self.membership(conn, owner, now)
            prefs = conn.execute(select(preferences).where(preferences.c.owner == owner)).mappings().first()
            current = self.period(row, active)
            used = self.used(conn, owner, current)
        return {
            "enabled": self.settings.membership_enabled,
            "purchaseEnabled": bool(self.settings.membership_enabled and self.settings.apple_root_certificates
                                    and (self.settings.apple_environment == "Sandbox" or self.settings.apple_app_id)),
            "productID": self.settings.apple_subscription_product,
            "accountToken": str(account_token(owner)),
            "active": active,
            "expiresAt": max(row["period_end"], row["grace_end"] or row["period_end"]).replace(tzinfo=timezone.utc).isoformat() if active else None,
            "willRenew": None if not active or row["renewal"] is None else bool(row["renewal"]),
            "remaining": max(0, self.limit - used),
            "limit": self.limit,
            "model": prefs["model"] if active and prefs else "builtIn",
            "skin": prefs["skin"] if active and prefs else "classic",
        }

    def require_member(self, owner):
        if self.settings.membership_enabled and not self.status(owner)["active"]:
            raise StorageError(403, "MEMBERSHIP_REQUIRED", "开通轻记会员后可使用自定义模型。")

    def set_preferences(self, owner, *, model=None, skin=None):
        with self.engine.begin() as conn:
            self.lock_account(conn, owner)
            _, active = self.membership(conn, owner, utcnow())
            if not active and (model == "custom" or skin not in (None, "classic")):
                raise StorageError(403, "MEMBERSHIP_REQUIRED", "请先开通轻记会员。")
            current = conn.execute(select(preferences).where(preferences.c.owner == owner)).mappings().first()
            values = {
                "model": model if model is not None else (current["model"] if current else "builtIn"),
                "skin": skin if skin is not None else (current["skin"] if current else "classic"),
            }
            if current:
                conn.execute(update(preferences).where(preferences.c.owner == owner).values(**values))
            else:
                conn.execute(insert(preferences).values(owner=owner, **values))

    def purge_expired(self):
        with self.engine.begin() as conn:
            conn.execute(delete(jobs).where(jobs.c.expires_at <= utcnow()))

    def reserve(self, owner, job_id, fingerprint, answer_hash):
        refining = answer_hash is not None
        now = utcnow()
        with self.engine.begin() as conn:
            self.lock_account(conn, owner)
            row, active = self.membership(conn, owner, now)
            period = self.period(row, active)
            conn.execute(delete(jobs).where(jobs.c.owner == owner, jobs.c.expires_at <= now))
            identity = (jobs.c.owner == owner, jobs.c.job_id == job_id)
            job = conn.execute(select(jobs).where(*identity)).mappings().first()
            if job and (job["fingerprint"] != fingerprint or job["period"] != period):
                raise StorageError(409, "ANALYSIS_CHANGED", "照片、模型或额度周期已变化，请重新开始分析。")
            if job and job["phase"].startswith("running"):
                raise StorageError(409, "ANALYSIS_RUNNING", "本次分析正在处理，请稍后重试。")
            if job and job["phase"] == "complete":
                if refining and job["answer_hash"] != answer_hash:
                    raise StorageError(409, "ANALYSIS_CHANGED", "本次分析已完成，请重新开始分析以修改答案。")
                return AnalysisSlot(job_id, None, job["output"], refining)
            if job and job["phase"] == "awaiting" and not refining:
                return AnalysisSlot(job_id, None, job["output"])
            if refining and not job:
                raise StorageError(409, "ANALYSIS_EXPIRED", "待确认的分析已过期，请重新开始分析。")
            if not job:
                pending = conn.execute(select(func.count()).select_from(jobs).where(
                    jobs.c.owner == owner, jobs.c.period == period, jobs.c.phase != "complete")).scalar_one()
                if self.used(conn, owner, period) + pending >= self.limit:
                    message = "本周期内置分析额度已用完。" if active else "免费体验已用完，可开通会员继续使用。"
                    raise StorageError(429, "AI_QUOTA_EXHAUSTED", message)
            lease = uuid4().hex
            values = {"phase": "running_refine" if refining else "running", "lease": lease, "answer_hash": answer_hash,
                      "expires_at": now + timedelta(seconds=240)}
            if job:
                conn.execute(update(jobs).where(*identity).values(**values))
            else:
                conn.execute(insert(jobs).values(owner=owner, job_id=job_id, period=period,
                                                fingerprint=fingerprint, **values))
            return AnalysisSlot(job_id, lease, refining=refining)

    def settle(self, owner, slot, output=None, awaiting=False):
        if not slot.lease:
            return
        with self.engine.begin() as conn:
            self.lock_account(conn, owner)
            identity = (jobs.c.owner == owner, jobs.c.job_id == slot.job_id, jobs.c.lease == slot.lease)
            job = conn.execute(select(jobs).where(*identity)).mappings().first()
            if not job:
                return
            if output is None and not slot.refining:
                conn.execute(delete(jobs).where(*identity))
                return
            if output is not None and not awaiting:
                period = job["period"]
                key = (usage.c.owner == owner, usage.c.period == period)
                changed = conn.execute(update(usage).where(*key).values(used=usage.c.used + 1))
                if not changed.rowcount:
                    conn.execute(insert(usage).values(owner=owner, period=period, used=1))
            phase = "awaiting" if awaiting or output is None else "complete"
            conn.execute(update(jobs).where(*identity).values(
                phase=phase, lease=None, output=output if output is not None else job["output"],
                expires_at=utcnow() + timedelta(minutes=10 if phase == "awaiting" else 20)))

    def apply_transaction(self, transaction, signed_at, *, owner=None, renewal=None, grace_end=None, restore=False):
        if (transaction.productId != self.settings.apple_subscription_product
                or not transaction.originalTransactionId or not transaction.transactionId
                or transaction.purchaseDate is None or transaction.expiresDate is None
                or transaction.appAccountToken is None):
            raise StorageError(400, "APPLE_TRANSACTION_INVALID", "订阅交易与轻记会员商品不匹配。")
        original_id = transaction.originalTransactionId
        token = UUID(str(transaction.appAccountToken))
        if owner is not None and token != account_token(owner):
            raise StorageError(403, "APPLE_ACCOUNT_MISMATCH", "这笔订阅属于另一个轻记账号。")
        with self.engine.begin() as conn:
            if owner is None:
                owner = conn.execute(select(subscriptions.c.owner).where(
                    subscriptions.c.original_id == original_id)).scalar_one_or_none()
                if owner is None:
                    owner = conn.execute(select(users.c.id).where(users.c.id == token.hex)).scalar_one_or_none()
                    if owner is None and account_token(self.settings.owner_id) == token:
                        owner = conn.execute(select(users.c.id).where(users.c.id == self.settings.owner_id)).scalar_one_or_none()
                if owner is None:
                    return
            self.lock_account(conn, owner)
            current = conn.execute(select(subscriptions).where(subscriptions.c.owner == owner)).mappings().first()
            period_start = apple_time(transaction.purchaseDate)
            if current and (period_start < current["period_start"] or
                            (period_start == current["period_start"] and signed_at <= current["signed_at"])):
                return
            values = dict(
                original_id=original_id, transaction_id=transaction.transactionId, period_start=period_start,
                period_end=apple_time(transaction.expiresDate), grace_end=grace_end,
                revoked_at=apple_time(transaction.revocationDate) if transaction.revocationDate is not None else None,
                signed_at=signed_at, renewal=renewal,
            )
            if restore and current and current["original_id"] == original_id:
                values["renewal"] = current["renewal"]
            if current:
                conn.execute(update(subscriptions).where(subscriptions.c.owner == owner).values(**values))
            else:
                conn.execute(insert(subscriptions).values(owner=owner, **values))
