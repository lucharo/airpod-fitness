# /// script
# requires-python = ">=3.11"
# dependencies = ["pyjwt[crypto]==2.10.1", "requests==2.32.5"]
# ///
"""Minimal App Store Connect API client. Uses ASC_KEY_PATH, ASC_KEY_ID and ASC_ISSUER_ID when set
(CI), otherwise the key in ~/.appstoreconnect.

uv run tools/asc.py GET '/v1/bundleIds?filter[identifier]=lucharo.airposture'
uv run tools/asc.py POST /v1/betaGroups '{"data": {...}}'
uv run tools/asc.py next-build         print one above the latest uploaded build number
uv run tools/asc.py profiles <dir>     install the profile ExportOptions-manual.plist names into <dir>
uv run tools/asc.py wait <build>       wait until Apple has processed a build, fail if it refused it

`wait` exists because an upload that succeeds can still fail Apple's processing, and such a build
may never appear in the build list, so running out of time means refused, or Apple is slow.
"""
import base64
import json
import os
import pathlib
import plistlib
import sys
import time

import jwt
import requests

API = "https://api.appstoreconnect.apple.com"
APP_ID = "6830647347"
ROOT = pathlib.Path.home() / ".appstoreconnect"
EXPORT_OPTIONS = pathlib.Path(__file__).parents[1] / "apps/air-posture/tools/ExportOptions-manual.plist"
WAIT_MINUTES = 30  # Apple: processing takes up to 30 minutes
POLL_SECONDS = 30


def token() -> str:
    key_id = os.environ.get("ASC_KEY_ID", "AZ756K8XB6")
    path = os.environ.get("ASC_KEY_PATH", ROOT / "private_keys" / f"AuthKey_{key_id}.p8")
    issuer = os.environ.get("ASC_ISSUER_ID") or (ROOT / "issuer_id").read_text().strip()
    now = int(time.time())
    return jwt.encode(
        {"iss": issuer, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"},
        pathlib.Path(path).read_text(), algorithm="ES256", headers={"kid": key_id, "typ": "JWT"},
    )


def request(method: str, path: str, body=None, params=None) -> requests.Response:
    return requests.request(
        method, API + path, params=params,
        headers={"Authorization": f"Bearer {token()}"}, json=body, timeout=60,
    )


def data(path: str, **params: str) -> list[dict]:
    response = request("GET", path, params=params)
    response.raise_for_status()
    return response.json()["data"]


def next_build() -> None:
    latest = data("/v1/builds", **{"filter[app]": APP_ID, "sort": "-uploadedDate", "limit": "1"})
    print(int(latest[0]["attributes"]["version"]) + 1)


def install_profiles(directory: pathlib.Path) -> None:
    names = plistlib.loads(EXPORT_OPTIONS.read_bytes())["provisioningProfiles"].values()
    directory.mkdir(parents=True, exist_ok=True)
    for name in names:
        found = data("/v1/profiles", **{"filter[name]": name, "filter[profileState]": "ACTIVE"})
        if len(found) != 1:
            sys.exit(f'expected one active profile named "{name}", found {len(found)}')
        attributes = found[0]["attributes"]
        path = directory / f"{attributes['uuid']}.mobileprovision"
        path.write_bytes(base64.b64decode(attributes["profileContent"]))
        print(f'{name}: {path.name}, expires {attributes["expirationDate"]}')


def wait_for_build(build: str) -> None:
    deadline = time.monotonic() + WAIT_MINUTES * 60
    state = "not listed yet"
    while time.monotonic() < deadline:
        try:
            found = data("/v1/builds", **{"filter[app]": APP_ID, "filter[version]": build})
        except requests.RequestException as error:  # a blip must not fail a build that uploaded
            print(f"build {build}: {error}, retrying", flush=True)
            time.sleep(POLL_SECONDS)
            continue
        if found:
            state = found[0]["attributes"]["processingState"]
            if state == "VALID":
                print(f"build {build} is processed and ready for TestFlight")
                return
            if state != "PROCESSING":
                sys.exit(f"Apple refused build {build}: {state}")
        print(f"build {build}: {state}", flush=True)
        time.sleep(POLL_SECONDS)
    sys.exit(f"build {build} is still '{state}' after {WAIT_MINUTES} minutes: refused by Apple, or Apple is slow")


def main() -> None:
    match sys.argv[1:]:
        case ["next-build"]:
            next_build()
        case ["profiles", directory]:
            install_profiles(pathlib.Path(directory))
        case ["wait", build]:
            wait_for_build(build)
        case [("GET" | "POST" | "PATCH" | "DELETE") as method, path, *body]:
            r = request(method, path, json.loads(body[0]) if body else None)
            print(r.status_code)
            print(json.dumps(r.json(), indent=1) if r.content else "")
        case _:
            sys.exit(__doc__)


if __name__ == "__main__":
    main()
