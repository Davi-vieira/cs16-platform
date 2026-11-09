import unittest
import sys
import os

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from app.security.auth import (
    hash_password,
    verify_password,
    create_access_token,
    generate_link_code,
    ROLE_HIERARCHY,
)
from jose import jwt

SECRET_KEY = os.environ.get("SECRET_KEY", "vieira_strike_default_secret_key_change_in_prod")


class TestSecurity(unittest.TestCase):
    def test_password_hashing(self):
        password = "minha_senha_super_segura_123"
        hashed = hash_password(password)

        self.assertNotEqual(hashed, password)
        self.assertTrue(verify_password(password, hashed))
        self.assertFalse(verify_password("senha_errada", hashed))

    def test_create_and_decode_token(self):
        player_id = "123e4567-e89b-12d3-a456-426614174000"
        roles = ["administrator"]
        token = create_access_token(player_id, roles)

        payload = jwt.decode(token, SECRET_KEY, algorithms=["HS256"])
        self.assertEqual(payload["sub"], player_id)
        self.assertEqual(payload["roles"], roles)
        self.assertIn("exp", payload)

    def test_generate_link_code(self):
        code = generate_link_code()
        self.assertEqual(len(code), 8)
        self.assertTrue(code.isupper() or code.isalnum())

    def test_role_hierarchy(self):
        self.assertIn("owner", ROLE_HIERARCHY)
        self.assertIn("administrator", ROLE_HIERARCHY)
        self.assertIn("moderator", ROLE_HIERARCHY)
        self.assertIn("support", ROLE_HIERARCHY)

        self.assertGreater(ROLE_HIERARCHY.index("owner"), ROLE_HIERARCHY.index("administrator"))
        self.assertGreater(ROLE_HIERARCHY.index("administrator"), ROLE_HIERARCHY.index("moderator"))
        self.assertGreater(ROLE_HIERARCHY.index("moderator"), ROLE_HIERARCHY.index("support"))


if __name__ == "__main__":
    unittest.main()
