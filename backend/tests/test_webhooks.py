import unittest
import hmac
import hashlib
import sys
import os

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
from app.api.webhooks import verify_signature

WEBHOOK_SECRET = os.environ.get("PAYMENT_WEBHOOK_SECRET", "vieira_strike_webhook_secret_change_in_prod")


class TestWebhooks(unittest.TestCase):
    def test_verify_signature_valid(self):
        payload = b'{"reference": "PIX_12345", "status": "confirmed", "amount": 5000}'
        signature = hmac.new(WEBHOOK_SECRET.encode(), payload, hashlib.sha256).hexdigest()
        self.assertTrue(verify_signature(payload, signature))

    def test_verify_signature_invalid(self):
        payload = b'{"reference": "PIX_12345", "status": "confirmed", "amount": 5000}'
        invalid_sig = "a" * 64
        self.assertFalse(verify_signature(payload, invalid_sig))

    def test_verify_signature_tampered_payload(self):
        payload = b'{"reference": "PIX_12345", "status": "confirmed", "amount": 5000}'
        signature = hmac.new(WEBHOOK_SECRET.encode(), payload, hashlib.sha256).hexdigest()
        tampered_payload = b'{"reference": "PIX_12345", "status": "confirmed", "amount": 999999}'
        self.assertFalse(verify_signature(tampered_payload, signature))


if __name__ == "__main__":
    unittest.main()
