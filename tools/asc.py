# /// script
# dependencies = ["pyjwt[crypto]", "requests"]
# ///
"""Minimal App Store Connect API client using the key in ~/.appstoreconnect.

uv run tools/asc.py GET /v1/bundleIds?filter[identifier]=lucharo.airposture
uv run tools/asc.py POST /v1/bundleIds '{"data": {...}}'
"""
import json
import pathlib
import sys
import time

import jwt
import requests

KEY_ID = "AZ756K8XB6"
ROOT = pathlib.Path.home() / ".appstoreconnect"


def token() -> str:
    key = (ROOT / "private_keys" / f"AuthKey_{KEY_ID}.p8").read_text()
    issuer = (ROOT / "issuer_id").read_text().strip()
    now = int(time.time())
    return jwt.encode(
        {"iss": issuer, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"},
        key, algorithm="ES256", headers={"kid": KEY_ID, "typ": "JWT"},
    )


def main() -> None:
    method, path = sys.argv[1], sys.argv[2]
    body = json.loads(sys.argv[3]) if len(sys.argv) > 3 else None
    r = requests.request(
        method, "https://api.appstoreconnect.apple.com" + path,
        headers={"Authorization": f"Bearer {token()}"}, json=body, timeout=60,
    )
    print(r.status_code)
    print(json.dumps(r.json(), indent=1) if r.content else "")


if __name__ == "__main__":
    main()
