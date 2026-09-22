#!/usr/bin/env python3
"""Generate a six-digit fixture TOTP with enough time left to enter it."""

import base64
import hashlib
import hmac
import os
import struct
import time


def totp(secret, timestamp):
    if not secret:
        raise ValueError("TOTP_SECRET is required")
    if timestamp < 0:
        raise ValueError("TOTP_TIME must be a non-negative integer")
    key = base64.b32decode(secret.upper() + "=" * (-len(secret) % 8))
    digest = hmac.new(key, struct.pack(">Q", timestamp // 30), hashlib.sha1).digest()
    offset = digest[-1] & 15
    value = struct.unpack(">I", digest[offset:offset + 4])[0] & 0x7FFFFFFF
    return f"{value % 1_000_000:06d}"


def current_time(min_validity):
    if not 0 <= min_validity <= 30:
        raise ValueError("TOTP_MIN_VALIDITY_SECONDS must be between 0 and 30")
    remaining = 30 - time.time() % 30
    if remaining < min_validity:
        time.sleep(remaining + 0.1)
    return int(time.time())


if __name__ == "__main__":
    timestamp = (
        int(os.environ["TOTP_TIME"]) if "TOTP_TIME" in os.environ
        else current_time(int(os.environ.get("TOTP_MIN_VALIDITY_SECONDS", "0")))
    )
    print(totp(os.environ["TOTP_SECRET"], timestamp))
