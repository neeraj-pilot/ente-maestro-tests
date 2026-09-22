import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("totp", Path(__file__).resolve().parent / "current-totp.py")
totp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(totp)


class TotpTests(unittest.TestCase):
    def test_rfc6238_sha1_vectors_truncated_to_six_digits(self):
        secret = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
        for timestamp, expected in [(59, "287082"), (1111111109, "081804"), (1111111111, "050471"), (1234567890, "005924"), (2000000000, "279037"), (20000000000, "353130")]:
            with self.subTest(timestamp=timestamp):
                self.assertEqual(totp.totp(secret, timestamp), expected)
        self.assertEqual(totp.totp(secret.lower(), 59), "287082")

    def test_base32_padding(self):
        self.assertEqual(totp.totp("MZXW6", 60), totp.totp("MZXW6===", 60))

    def test_reject_invalid_input(self):
        for secret, timestamp in [("", 60), ("not-base32!", 60), ("MZXW6", -1)]:
            with self.subTest(secret=secret, timestamp=timestamp), self.assertRaises(ValueError):
                totp.totp(secret, timestamp)
        for minimum in (-1, 31):
            with self.assertRaises(ValueError):
                totp.current_time(minimum)

    def test_wait_only_when_validity_is_short(self):
        for now, after, expected_sleep in [(35, 35, None), (55, 60.1, 5.1)]:
            with self.subTest(now=now), patch.object(totp.time, "time", side_effect=[now, after]), patch.object(totp.time, "sleep") as sleep:
                self.assertEqual(totp.current_time(20), int(after))
                if expected_sleep is None:
                    sleep.assert_not_called()
                else:
                    sleep.assert_called_once_with(expected_sleep)
