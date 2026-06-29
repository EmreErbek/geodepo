#!/usr/bin/env python3
"""Production dashboard fix via REST API."""
from __future__ import annotations

import json
import sys
import time
import urllib.error
import urllib.request

BASE = "https://baserow-backend-production-4412.up.railway.app"
EMAIL = "emre2372@yahoo.com"
PASSWORD = "asd123asd"
DASHBOARD_ID = 14

WIDGETS = [
    ("Açık Teklifler", 27, 219, []),
    ("Devam Eden Projeler", 29, 259, []),
    ("Ödeme Kayıtları", 30, 315, []),
]


def api(method: str, path: str, body: dict | None = None, token: str | None = None):
    url = f"{BASE}{path}"
    headers = {"Accept": "application/json"}
    data = None
    if body is not None:
        data = json.dumps(body, ensure_ascii=False).encode("utf-8")
        headers["Content-Type"] = "application/json; charset=utf-8"
    if token:
        headers["Authorization"] = f"JWT {token}"
    for attempt in range(1, 8):
        req = urllib.request.Request(url, data=data, headers=headers, method=method)
        try:
            with urllib.request.urlopen(req, timeout=45) as resp:
                raw = resp.read().decode("utf-8")
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as e:
            err = e.read().decode("utf-8", errors="replace")
            raise RuntimeError(f"{method} {path} -> {e.code}: {err}") from e
        except (urllib.error.URLError, TimeoutError):
            if attempt < 7:
                time.sleep(attempt * 2)
                continue
            raise
    raise RuntimeError("unreachable")


def main() -> int:
    token = api("POST", "/api/user/token-auth/", {"username": EMAIL, "password": PASSWORD})[
        "token"
    ]
    print("login ok")

    integrations = api("GET", f"/api/application/{DASHBOARD_ID}/integrations/", token=token)
    if not integrations:
        created = api(
            "POST",
            f"/api/application/{DASHBOARD_ID}/integrations/",
            {"type": "local_baserow", "name": "Local Baserow"},
            token=token,
        )
        print(f"integration created: {created['id']}")
    else:
        print(f"integration: {integrations[0]['id']}")

    data_sources = {
        int(ds["id"]): ds
        for ds in api("GET", f"/api/dashboard/{DASHBOARD_ID}/data-sources/", token=token)
    }
    widgets = api("GET", f"/api/dashboard/{DASHBOARD_ID}/widgets/", token=token)
    by_title = {w["title"]: w for w in widgets}

    for w in list(widgets):
        ds = data_sources.get(w["data_source_id"])
        if not ds or not ds.get("integration_id"):
            api("DELETE", f"/api/dashboard/widgets/{w['id']}/", token=token)
            print(f"deleted widget {w['id']} ({w['title']})")
            by_title.pop(w["title"], None)

    for title, table_id, field_id, filters in WIDGETS:
        widget = by_title.get(title)
        if not widget:
            widget = api(
                "POST",
                f"/api/dashboard/{DASHBOARD_ID}/widgets/",
                {"title": title, "description": "", "type": "summary"},
                token=token,
            )
            print(f"created widget {title} #{widget['id']} ds={widget['data_source_id']}")
            by_title[title] = widget

        ds_id = widget["data_source_id"]
        api(
            "PATCH",
            f"/api/dashboard/data-sources/{ds_id}/",
            {
                "table_id": table_id,
                "field_id": field_id,
                "aggregation_type": "count",
                "filters": filters,
                "filter_type": "AND",
            },
            token=token,
        )
        dispatch = api("POST", f"/api/dashboard/data-sources/{ds_id}/dispatch/", {}, token=token)
        value = dispatch.get("data", {}).get("value", dispatch)
        print(f"dispatch {title}: {value}")

    print("done")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1) from exc