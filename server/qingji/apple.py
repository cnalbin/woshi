from functools import cached_property
from pathlib import Path

from appstoreserverlibrary.models.Environment import Environment
from appstoreserverlibrary.signed_data_verifier import SignedDataVerifier, VerificationException, VerificationStatus

from .membership import apple_time
from .storage import StorageError


class AppleSubscriptions:
    def __init__(self, settings, memberships):
        self.settings = settings
        self.memberships = memberships

    @cached_property
    def verifier(self):
        settings = self.settings
        if not settings.membership_enabled or not settings.apple_root_certificates:
            raise StorageError(503, "PURCHASE_UNAVAILABLE", "Apple 订阅尚未开放。")
        try:
            roots = [Path(path.strip()).read_bytes() for path in settings.apple_root_certificates.split(",") if path.strip()]
            if not roots:
                raise ValueError("Apple roots missing")
            return SignedDataVerifier(roots, True, Environment(settings.apple_environment),
                                      settings.apple_bundle_id, settings.apple_app_id)
        except (OSError, ValueError):
            raise StorageError(503, "PURCHASE_UNAVAILABLE", "Apple 订阅验证暂不可用。") from None

    @staticmethod
    def verify(decoder, data):
        try:
            return decoder(data)
        except VerificationException as error:
            if error.status == VerificationStatus.RETRYABLE_VERIFICATION_FAILURE:
                raise StorageError(503, "APPLE_VERIFY_RETRY", "Apple 交易暂时无法验证，请稍后重试。") from None
            raise StorageError(400, "APPLE_SIGNATURE_INVALID", "Apple 交易签名验证失败。") from None

    def transaction(self, owner, data):
        value = self.verify(self.verifier.verify_and_decode_signed_transaction, data)
        if value.signedDate is None:
            raise StorageError(400, "APPLE_TRANSACTION_INVALID", "Apple 交易缺少签发时间。")
        self.memberships.apply_transaction(value, apple_time(value.signedDate), owner=owner, restore=True)

    def notification(self, data):
        notice = self.verify(self.verifier.verify_and_decode_notification, data)
        if not notice.data or not notice.data.signedTransactionInfo or notice.signedDate is None:
            return
        value = self.verify(self.verifier.verify_and_decode_signed_transaction, notice.data.signedTransactionInfo)
        if value.productId != self.settings.apple_subscription_product:
            return
        renewal = None
        grace_end = None
        if notice.data.signedRenewalInfo:
            info = self.verify(self.verifier.verify_and_decode_renewal_info, notice.data.signedRenewalInfo)
            if info.originalTransactionId != value.originalTransactionId:
                raise StorageError(400, "APPLE_TRANSACTION_INVALID", "Apple 续费信息与交易不匹配。")
            if info.autoRenewStatus is not None:
                renewal = info.autoRenewStatus.value == 1
            if info.gracePeriodExpiresDate is not None:
                grace_end = apple_time(info.gracePeriodExpiresDate)
        self.memberships.apply_transaction(value, apple_time(notice.signedDate), renewal=renewal, grace_end=grace_end)
