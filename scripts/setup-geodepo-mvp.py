#!/usr/bin/env python3
"""GEO DEPO MVP: Operasyon formu + Sistem automation + Dashboard kokpit."""
from __future__ import annotations

import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ID_MAP_PATH = ROOT / "deploy" / "geodepo" / "focus-lists-id-map.json"
CONFIG_PATH = ROOT / "deploy" / "geodepo" / "applications-config.json"

WORKSPACE_ID = 2
DATABASE_ID = 11

FORM_VIEW_NAME = "Ödeme Girişi"
AUTOMATION_APP_NAME = "GEO DEPO Sistem"
AUTOMATION_WORKFLOW_NAME = "Teklif Kabul → Proje"
DASHBOARD_APP_NAME = "GEO DEPO Kokpit"

TEKLIF_STATUS_WON = "Kabul Edildi"
RECORD_TYPE_PROJECT = "Proje"


class Api:
    def __init__(self, base: str, email: str, password: str):
        self.base = base.rstrip("/")
        self.token = self._login(email, password)

    def _login(self, email: str, password: str) -> str:
        r = self._raw("POST", "/api/user/token-auth/", {"email": email, "password": password})
        return r["token"]

    def _raw(self, method: str, path: str, body: dict | None = None):
        url = f"{self.base}{path}"
        data = None
        headers = {"Accept": "application/json"}
        if body is not None:
            data = json.dumps(body, ensure_ascii=False).encode("utf-8")
            headers["Content-Type"] = "application/json; charset=utf-8"
        if getattr(self, "token", None):
            headers["Authorization"] = f"JWT {self.token}"
        for attempt in range(1, 10):
            req = urllib.request.Request(url, data=data, headers=headers, method=method)
            try:
                with urllib.request.urlopen(req, timeout=120) as resp:
                    raw = resp.read().decode("utf-8")
                    return json.loads(raw) if raw else {}
            except urllib.error.HTTPError as e:
                err = e.read().decode("utf-8", errors="replace")
                if e.code in (502, 503, 504) and attempt < 9:
                    time.sleep(attempt * 2)
                    continue
                raise RuntimeError(f"{method} {path} -> {e.code}: {err}") from e
            except urllib.error.URLError:
                if attempt < 9:
                    time.sleep(attempt * 2)
                    continue
                raise
        raise RuntimeError("unreachable")

    def get(self, path: str):
        return self._raw("GET", path)

    def post(self, path: str, body: dict):
        return self._raw("POST", path, body)

    def patch(self, path: str, body: dict):
        return self._raw("PATCH", path, body)

    def delete(self, path: str):
        return self._raw("DELETE", path)


def load_env() -> dict[str, str]:
    env_file = ROOT / ".env"
    if env_file.exists():
        for line in env_file.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            k, v = k.strip(), v.strip()
            if k and v and k not in os.environ:
                os.environ[k] = v
    return {
        "base": os.environ.get("GEODEPO_BASEROW_URL", "http://localhost:8000").rstrip("/"),
        "email": os.environ.get("GEODEPO_BASEROW_EMAIL", ""),
        "password": os.environ.get("GEODEPO_BASEROW_PASSWORD", ""),
    }


def load_id_map() -> dict:
    return json.loads(ID_MAP_PATH.read_text(encoding="utf-8"))


def load_config() -> dict:
    if CONFIG_PATH.exists():
        return json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    return {"version": 1, "workspace_id": WORKSPACE_ID}


def save_config(cfg: dict):
    CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
    CONFIG_PATH.write_text(json.dumps(cfg, ensure_ascii=False, indent=2), encoding="utf-8")


def find_application(apps: list, name: str, app_type: str | None = None):
    for app in apps:
        if app.get("name") == name and (app_type is None or app.get("type") == app_type):
            return app
    return None


def find_view(views: list, name: str, view_type: str = "form"):
    for v in views:
        if v.get("name") == name and v.get("type") == view_type:
            return v
    return None


def field_id(id_map: dict, table: str, name: str) -> int:
    return int(id_map["fields"][table][name])


def formula(expr: str) -> dict:
    return {"mode": "simple", "version": "0.1", "formula": expr}


def table_id(id_map: dict, table: str) -> int:
    return int(id_map["tables"][table])


def setup_payment_form(api: Api, id_map: dict, cfg: dict) -> dict:
    print("\n=== 1) OPERASYON: Ödeme Girişi formu ===")
    payment_table = table_id(id_map, "Ödeme Takibi")
    views = api.get(f"/api/database/views/table/{payment_table}/")
    existing = find_view(views, FORM_VIEW_NAME)
    if existing:
        print(f"  Mevcut form görünümü: {existing['id']}")
        view_id = existing["id"]
    else:
        created = api.post(
            f"/api/database/views/table/{payment_table}/",
            {"name": FORM_VIEW_NAME, "type": "form"},
        )
        view_id = created["id"]
        print(f"  Oluşturuldu form görünümü: {view_id}")

    enabled_fields = [
        ("Kayıt Adı", 1, True),
        ("Üst Görev", 2, True),
        ("Gelen Ödeme", 3, False),
        ("Ödeme Tarihi", 4, False),
        ("Ödeme Durumu", 5, False),
        ("Ödeme Gelen Yer", 6, False),
        ("Kayıt Türü", 7, False),
        ("Açıklama", 8, False),
    ]
    field_options = {}
    for fname, order, required in enabled_fields:
        fid = field_id(id_map, "Ödeme Takibi", fname)
        field_options[str(fid)] = {
            "enabled": True,
            "required": required,
            "order": order,
            "name": fname if fname != "Açıklama" else "Not",
        }

    api.patch(
        f"/api/database/views/{view_id}/field-options/",
        {"field_options": field_options},
    )
    print(f"  Alanlar yapılandırıldı ({len(field_options)} alan)")

    return {
        "table_id": payment_table,
        "view_id": view_id,
        "url_hint": f"/database/{DATABASE_ID}/table/{payment_table}/{view_id}",
    }


def get_database_app_id(api: Api) -> int:
    apps = api.get(f"/api/applications/workspace/{WORKSPACE_ID}/")
    for app in apps:
        if app.get("type") == "database" and app.get("id") == DATABASE_ID:
            return app["id"]
    for app in apps:
        if app.get("type") == "database":
            return app["id"]
    raise RuntimeError("Database application bulunamadı")


def setup_automation(api: Api, id_map: dict, cfg: dict) -> dict:
    print("\n=== 2) SİSTEM: Teklif Kabul → Devam Eden automation ===")
    apps = api.get(f"/api/applications/workspace/{WORKSPACE_ID}/")
    automation = find_application(apps, AUTOMATION_APP_NAME, "automation")
    if not automation:
        automation = api.post(
            f"/api/applications/workspace/{WORKSPACE_ID}/",
            {"name": AUTOMATION_APP_NAME, "type": "automation"},
        )
        print(f"  Automation uygulaması oluşturuldu: {automation['id']}")
    else:
        print(f"  Mevcut automation uygulaması: {automation['id']}")

    automation_id = automation["id"]
    automation_detail = api.get(f"/api/applications/{automation_id}/")
    workflows = automation_detail.get("workflows") or []
    workflow = None
    for wf in workflows:
        if wf.get("name") == AUTOMATION_WORKFLOW_NAME:
            workflow = wf
            break
    if not workflow:
        workflow = api.post(
            f"/api/automation/{automation_id}/workflows/",
            {"name": AUTOMATION_WORKFLOW_NAME},
        )
        print(f"  Workflow oluşturuldu: {workflow['id']}")
    else:
        print(f"  Mevcut workflow: {workflow['id']}")

    workflow_id = workflow["id"]
    nodes = api.get(f"/api/automation/workflow/{workflow_id}/nodes/")
    trigger = next(
        (
            n
            for n in nodes
            if n["type"] in ("local_baserow_rows_updated", "local_baserow_rows_created")
        ),
        None,
    )
    if not trigger:
        trigger = api.post(
            f"/api/automation/workflow/{workflow_id}/nodes/",
            {"type": "local_baserow_rows_updated"},
        )
        print(f"  Trigger oluşturuldu: {trigger['id']}")
        nodes = [trigger]

    integrations = api.get(f"/api/application/{automation_id}/integrations/")
    if not integrations:
        created_int = api.post(
            f"/api/application/{automation_id}/integrations/",
            {"type": "local_baserow", "name": "Local Baserow"},
        )
        integration_id = created_int["id"]
        print(f"  Local Baserow integration oluşturuldu: {integration_id}")
    else:
        integration_id = integrations[0]["id"]

    teklif_table = table_id(id_map, "Teklif")
    devam_table = table_id(id_map, "Devam Eden İşler")
    teklif_status_field = field_id(id_map, "Teklif", "Teklif Durumu")
    teklif_name_field = field_id(id_map, "Teklif", "Teklif Adı")
    devam_name_field = field_id(id_map, "Devam Eden İşler", "Görev Adı")
    devam_record_type_field = field_id(id_map, "Devam Eden İşler", "Kayıt Türü")
    devam_clickup_id_field = field_id(id_map, "Devam Eden İşler", "ClickUp Task ID")

    # Trigger: Teklif tablosunda satır güncellendi + Teklif Durumu = Kabul Edildi
    if trigger["type"] != "local_baserow_rows_updated":
        trigger = api.post(
            f"/api/automation/node/{trigger['id']}/replace/",
            {"new_type": "local_baserow_rows_updated"},
        )
        print(f"  Trigger rows_updated olarak güncellendi: {trigger['id']}")

    api.patch(
        f"/api/automation/node/{trigger['id']}/",
        {
            "label": "Teklif güncellendi",
            "service": {
                "type": "local_baserow_rows_updated",
                "integration_id": integration_id,
                "table_id": teklif_table,
                "filters": [
                    {
                        "field_id": teklif_status_field,
                        "type": "single_select_equal",
                        "value": TEKLIF_STATUS_WON,
                    }
                ],
                "filter_type": "AND",
            },
        },
    )
    print("  Trigger servisi yapılandırıldı (Teklif + Kabul Edildi filtresi)")

    action = next((n for n in nodes if n["type"] == "local_baserow_create_row"), None)
    if not action:
        action = api.post(
            f"/api/automation/workflow/{workflow_id}/nodes/",
            {
                "type": "local_baserow_create_row",
                "reference_node_id": trigger["id"],
                "position": "south",
                "output": "",
            },
        )
        print(f"  Create row aksiyonu eklendi: {action['id']}")

    # Formüller trigger node id'sine bağlı; publish sırasında id_mapping ile yeniden yazılır.
    name_ref = f"previous_node.{trigger['id']}.0.field_{teklif_name_field}"
    row_ref = f"previous_node.{trigger['id']}.0.id"
    api.patch(
        f"/api/automation/node/{action['id']}/",
        {
            "label": "Devam Eden İş oluştur",
            "service": {
                "type": "local_baserow_upsert_row",
                "integration_id": integration_id,
                "table_id": devam_table,
                "field_mappings": [
                    {
                        "field_id": devam_name_field,
                        "enabled": True,
                        "value": formula(f"get('{name_ref}')"),
                    },
                    {
                        "field_id": devam_record_type_field,
                        "enabled": True,
                        "value": formula(f"'{RECORD_TYPE_PROJECT}'"),
                    },
                    {
                        "field_id": devam_clickup_id_field,
                        "enabled": True,
                        "value": formula(f"concat('teklif-', get('{row_ref}'))"),
                    },
                ],
            },
        },
    )
    print("  Create row field mapping yapılandırıldı")

    publish_result = publish_workflow(api, workflow_id)

    return {
        "automation_id": automation_id,
        "workflow_id": workflow_id,
        "trigger_id": trigger["id"],
        "action_id": action["id"],
        **publish_result,
    }


def cancel_pending_publish_jobs(api: Api, workflow_id: int) -> int:
    jobs = api.get(
        "/api/jobs/?limit=50&job_type_name=publish_automation_workflow&states=pending"
    )
    cancelled = 0
    for job in jobs.get("jobs", []):
        try:
            api.post(f"/api/jobs/{job['id']}/cancel/", {})
            cancelled += 1
        except RuntimeError:
            pass
    if cancelled:
        print(f"  {cancelled} takılı publish job iptal edildi")
    return cancelled


def publish_workflow(api: Api, workflow_id: int, timeout_sec: int = 180) -> dict:
    wf = api.get(f"/api/automation/workflows/{workflow_id}/")
    force = os.environ.get("GEODEPO_FORCE_REPUBLISH", "").lower() in ("1", "true", "yes")
    if wf.get("state") == "live" and not force:
        print(f"  Workflow zaten yayında (state=live, {wf.get('published_on')})")
        print("  Field mapping güncellediyseniz: GEODEPO_FORCE_REPUBLISH=1 ile yeniden yayınlayın")
        return {"publish_state": "live", "publish_job_id": None}

    cancel_pending_publish_jobs(api, workflow_id)
    try:
        job = api.post(f"/api/automation/workflows/{workflow_id}/publish/async/", {})
    except RuntimeError as e:
        print(f"  Publish uyarısı: {e}")
        return {"publish_state": "error", "publish_job_id": None}

    job_id = job.get("id")
    print(f"  Publish job başlatıldı: #{job_id}")
    deadline = time.time() + timeout_sec
    while time.time() < deadline:
        polled = api.get(f"/api/jobs/{job_id}/")
        state = polled.get("state")
        if state == "finished":
            wf = api.get(f"/api/automation/workflows/{workflow_id}/")
            print(f"  Yayınlandı: state={wf.get('state')}, {wf.get('published_on')}")
            return {"publish_state": wf.get("state"), "publish_job_id": job_id}
        if state in ("failed", "cancelled"):
            err = polled.get("human_readable_error", "")
            print(f"  Publish başarısız ({state}): {err}")
            return {"publish_state": state, "publish_job_id": job_id}
        time.sleep(3)

    print(f"  Publish zaman aşımı (job #{job_id} hâlâ pending olabilir)")
    print("  Celery Worker export kuyruğunu dinliyor mu kontrol edin:")
    print("  scripts/configure-geodepo-celery-worker.ps1")
    return {"publish_state": "pending", "publish_job_id": job_id}


def ensure_dashboard_integration(api: Api, dashboard_id: int) -> int:
    integrations = api.get(f"/api/application/{dashboard_id}/integrations/")
    if not integrations:
        created = api.post(
            f"/api/application/{dashboard_id}/integrations/",
            {"type": "local_baserow", "name": "Local Baserow"},
        )
        print(f"  Local Baserow integration oluşturuldu: {created['id']}")
        return created["id"]
    integration_id = integrations[0]["id"]
    print(f"  Mevcut Local Baserow integration: {integration_id}")
    return integration_id


def data_source_needs_rebuild(data_sources: dict[int, dict], data_source_id: int) -> bool:
    ds = data_sources.get(data_source_id)
    return not ds or not ds.get("integration_id")


def setup_dashboard(api: Api, id_map: dict, cfg: dict) -> dict:
    print("\n=== 3) OPERASYON KOKPİT: Dashboard widget'ları ===")
    apps = api.get(f"/api/applications/workspace/{WORKSPACE_ID}/")
    dashboard = find_application(apps, DASHBOARD_APP_NAME, "dashboard")
    if not dashboard:
        dashboard = api.post(
            f"/api/applications/workspace/{WORKSPACE_ID}/",
            {"name": DASHBOARD_APP_NAME, "type": "dashboard"},
        )
        print(f"  Dashboard oluşturuldu: {dashboard['id']}")
    else:
        print(f"  Mevcut dashboard: {dashboard['id']}")

    dashboard_id = dashboard["id"]
    ensure_dashboard_integration(api, dashboard_id)

    widgets_cfg = [
        (
            "Açık Teklifler",
            table_id(id_map, "Teklif"),
            field_id(id_map, "Teklif", "Teklif Adı"),
            "count",
            [],
        ),
        (
            "Devam Eden Projeler",
            table_id(id_map, "Devam Eden İşler"),
            field_id(id_map, "Devam Eden İşler", "Görev Adı"),
            "count",
            [],
        ),
        (
            "Ödeme Kayıtları",
            table_id(id_map, "Ödeme Takibi"),
            field_id(id_map, "Ödeme Takibi", "Kayıt Adı"),
            "count",
            [],
        ),
    ]

    existing_widgets = api.get(f"/api/dashboard/{dashboard_id}/widgets/")
    data_sources = {
        int(ds["id"]): ds for ds in api.get(f"/api/dashboard/{dashboard_id}/data-sources/")
    }
    widget_results = []
    for title, tbl_id, agg_field, agg_type, filters in widgets_cfg:
        widget = next((w for w in existing_widgets if w.get("title") == title), None)
        if widget and data_source_needs_rebuild(data_sources, widget["data_source_id"]):
            print(f"  Widget yeniden oluşturulacak (integration eksik): {title} (#{widget['id']})")
            api.delete(f"/api/dashboard/widgets/{widget['id']}/")
            widget = None

        if not widget:
            widget = api.post(
                f"/api/dashboard/{dashboard_id}/widgets/",
                {"title": title, "description": "", "type": "summary"},
            )
            print(f"  Widget oluşturuldu: {title} (#{widget['id']})")
        else:
            print(f"  Mevcut widget: {title} (#{widget['id']})")

        ds_id = widget["data_source_id"]
        body = {
            "table_id": tbl_id,
            "aggregation_type": agg_type,
            "filters": filters,
            "filter_type": "AND",
        }
        if agg_field:
            body["field_id"] = agg_field
        api.patch(f"/api/dashboard/data-sources/{ds_id}/", body)

        dispatch = api.post(f"/api/dashboard/data-sources/{ds_id}/dispatch/", {})
        count_val = dispatch.get("data", {}).get("value") if isinstance(dispatch.get("data"), dict) else dispatch
        print(f"  Dispatch OK: {title} -> {count_val}")

        widget_results.append({"title": title, "widget_id": widget["id"], "data_source_id": ds_id})

    return {"dashboard_id": dashboard_id, "widgets": widget_results}


def main():
    env = load_env()
    if not env["email"] or not env["password"]:
        sys.exit("GEODEPO_BASEROW_EMAIL/PASSWORD gerekli (.env)")

    step = os.environ.get("GEODEPO_MVP_STEP", "all").lower()
    id_map = load_id_map()
    cfg = load_config()
    api = Api(env["base"], env["email"], env["password"])

    if step in ("all", "operasyon", "form"):
        cfg["operasyon"] = setup_payment_form(api, id_map, cfg)
    if step in ("all", "sistem", "automation"):
        cfg["sistem"] = setup_automation(api, id_map, cfg)
    if step in ("all", "dashboard", "kokpit"):
        cfg["dashboard"] = setup_dashboard(api, id_map, cfg)
    cfg["updated_at"] = time.strftime("%Y-%m-%dT%H:%M:%S%z")
    save_config(cfg)

    print("\n=== Tamam ===")
    print(f"Config: {CONFIG_PATH}")
    print(json.dumps(cfg, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()