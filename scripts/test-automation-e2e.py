#!/usr/bin/env python3
"""Republish workflow and run Teklif Kabul → Proje E2E test."""
from __future__ import annotations

import json
import os
import sys
import time
import urllib.error
import urllib.request

BASE = os.environ.get(
    "GEODEPO_BASEROW_URL",
    "https://baserow-backend-production-4412.up.railway.app",
).rstrip("/")
EMAIL = os.environ.get("GEODEPO_BASEROW_EMAIL", "emre2372@yahoo.com")
PASSWORD = os.environ.get("GEODEPO_BASEROW_PASSWORD", "asd123asd")

WORKFLOW_ID = 4
TEKLIF_ROW_ID = 5
DEVAM_TABLE = 29
TEKLIF_STATUS_FIELD = "field_255"


def api(method: str, path: str, body: dict | None = None, token: str | None = None):
    headers = {"Accept": "application/json"}
    data = None
    if body is not None:
        data = json.dumps(body).encode()
        headers["Content-Type"] = "application/json"
    if token:
        headers["Authorization"] = f"JWT {token}"
    req = urllib.request.Request(BASE + path, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            raw = resp.read().decode()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        err = e.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"{method} {path} -> {e.code}: {err}") from e


def login() -> str:
    r = api("POST", "/api/user/token-auth/", {"email": EMAIL, "password": PASSWORD})
    return r["token"]


def poll_publish(token: str, job_id: int, timeout: int = 180) -> dict:
    deadline = time.time() + timeout
    while time.time() < deadline:
        job = api("GET", f"/api/jobs/{job_id}/", token=token)
        state = job.get("state")
        print(f"  publish job #{job_id}: {state}")
        if state in ("finished", "failed", "cancelled"):
            return job
        time.sleep(3)
    return {"state": "timeout"}


def inspect_published_formulas(token: str, automation_id: int = 13):
    """Check published action node field mapping formulas."""
    auto = api("GET", f"/api/automation/{automation_id}/", token=token)
    for wf in auto.get("workflows", []):
        for node in wf.get("automation_workflow_nodes", []):
            svc = node.get("service") or {}
            if svc.get("type") != "local_baserow_upsert_row":
                continue
            print(f"  published action node #{node['id']}:")
            for fm in svc.get("field_mappings", []):
                val = fm.get("value") or {}
                print(f"    field {fm.get('field_id')}: {val.get('formula', val)}")


def cleanup_empty_rows(token: str):
    rows = api(
        "GET",
        f"/api/database/rows/table/{DEVAM_TABLE}/?user_field_names=true&size=200",
        token=token,
    )
    deleted = 0
    for row in rows.get("results", []):
        if not row.get("ClickUp Task ID") and not row.get("Görev Adı"):
            api("DELETE", f"/api/database/rows/table/{DEVAM_TABLE}/{row['id']}/", token=token)
            print(f"  deleted empty row #{row['id']}")
            deleted += 1
    return deleted


def run_e2e(token: str) -> dict | None:
    api(
        "PATCH",
        f"/api/database/rows/table/27/{TEKLIF_ROW_ID}/",
        {TEKLIF_STATUS_FIELD: "Beklemede"},
        token=token,
    )
    print("  Teklif #5 -> Beklemede")
    time.sleep(2)
    api(
        "PATCH",
        f"/api/database/rows/table/27/{TEKLIF_ROW_ID}/",
        {TEKLIF_STATUS_FIELD: "Kabul Edildi"},
        token=token,
    )
    print("  Teklif #5 -> Kabul Edildi")

    for i in range(15):
        time.sleep(3)
        rows = api(
            "GET",
            f"/api/database/rows/table/{DEVAM_TABLE}/?user_field_names=true&size=200",
            token=token,
        )
        for row in rows.get("results", []):
            if row.get("ClickUp Task ID") == f"teklif-{TEKLIF_ROW_ID}":
                kayit = row.get("Kayıt Türü")
                if isinstance(kayit, dict):
                    kayit = kayit.get("value")
                return {
                    "id": row["id"],
                    "gorev": row.get("Görev Adı"),
                    "kayit": kayit,
                    "clickup": row.get("ClickUp Task ID"),
                }
        print(f"  waiting for row... ({i + 1}/15)")

    hist = api("GET", f"/api/automation/workflows/{WORKFLOW_ID}/history/?limit=1", token=token)
    if hist.get("results"):
        nodes = hist["results"][0].get("node_histories", [])
        action = next(
            (n for n in reversed(nodes) if n.get("node_type") == "local_baserow_create_row"),
            None,
        )
        if action:
            print(f"  last action result: {action.get('result')}")
    return None


def main():
    print(f"API: {BASE}")
    token = login()
    print("Login OK")

    health = api("GET", "/api/_health/full/", token=token)
    print(f"export queue: {health.get('celery_export_queue_size')}")

    wf = api("GET", f"/api/automation/workflows/{WORKFLOW_ID}/", token=token)
    print(f"workflow state: {wf.get('state')} ({wf.get('published_on')})")

    force = os.environ.get("GEODEPO_FORCE_REPUBLISH", "1").lower() in ("1", "true", "yes")
    if force:
        print("\n=== Republish ===")
        job = api("POST", f"/api/automation/workflows/{WORKFLOW_ID}/publish/async/", {}, token=token)
        result = poll_publish(token, job["id"])
        if result.get("state") != "finished":
            print(f"Publish failed: {result}")
            sys.exit(1)
        wf = api("GET", f"/api/automation/workflows/{WORKFLOW_ID}/", token=token)
        print(f"Published: {wf.get('state')} at {wf.get('published_on')}")

    print("\n=== Published formulas ===")
    inspect_published_formulas(token)

    print("\n=== Cleanup empty rows ===")
    cleanup_empty_rows(token)

    print("\n=== E2E test ===")
    match = run_e2e(token)
    if match and match.get("clickup") and match.get("gorev"):
        print(f"\nSUCCESS: Devam Eden #{match['id']}")
        print(f"  Görev Adı: {match['gorev']}")
        print(f"  Kayıt Türü: {match['kayit']}")
        print(f"  ClickUp Task ID: {match['clickup']}")
        return

    print("\nFAIL: Row created but fields empty or missing")
    sys.exit(1)


if __name__ == "__main__":
    main()