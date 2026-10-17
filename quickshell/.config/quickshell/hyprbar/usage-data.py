#!/usr/bin/env python3
"""Emit a credential-free AI usage snapshot for the Quickshell overlay."""

from __future__ import annotations

import datetime as dt
import fcntl
import json
import math
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

LOCAL_URL = "http://127.0.0.1:3002"
LOCAL_INTERVAL = 1
LOCAL_DOWN_INTERVAL = 15
LOCAL_COUNTERS = ("llamacpp:prompt_tokens_total", "llamacpp:tokens_predicted_total")
METRIC_LINE = re.compile(
    r"^(llamacpp:(?:prompt_tokens|tokens_predicted)_total)(?:\{[^}]*\})?\s+([0-9.eE+-]+)\s*$"
)
PROVIDER_IDS = ("codex", "claude_code", "zai", "pi", "openrouter")


def _state_path() -> Path:
    state_home = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state"))
    return state_home / "usage-dashboard" / "local-counter.json"


def _snapshot_cache_path() -> Path:
    cache_home = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache"))
    return cache_home / "ai-usage-dashboard.json"


def _persist_snapshot(snapshot: dict[str, Any]) -> None:
    path = _snapshot_cache_path()
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    temporary = path.with_name(path.name + f".{os.getpid()}.tmp")
    fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump(snapshot, stream, separators=(",", ":"), ensure_ascii=False)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
        os.chmod(path, 0o600)
    except Exception:
        temporary.unlink(missing_ok=True)
        raise


def _run(argv: list[str], timeout: int = 12) -> str:
    try:
        result = subprocess.run(
            argv,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            timeout=timeout,
            check=False,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
        return result.stdout if result.returncode == 0 else ""
    except (OSError, subprocess.TimeoutExpired):
        return ""


def _run_json(argv: list[str], timeout: int = 12) -> dict[str, Any] | None:
    try:
        result = subprocess.run(
            argv,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            timeout=timeout,
            check=False,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
        value = json.loads(result.stdout) if result.returncode == 0 else None
        return value if isinstance(value, dict) else None
    except (OSError, subprocess.TimeoutExpired, ValueError):
        return None


def _ai_usage() -> dict[str, Any] | None:
    command = Path.home() / ".local/bin/ai-usage"
    zsh = shutil.which("zsh")
    if not command.is_file() or not zsh:
        return None
    return _run_json([zsh, "-c", 'exec "$0" --json', str(command)], timeout=18)


def _openusage_period(command: str, start: dt.date, end: dt.date) -> dict[str, Any] | None:
    binary = shutil.which("openusage")
    if not binary:
        return None
    result = _run_json(
        [binary, command, "--json", "--offline", "--since", start.isoformat(), "--until", end.isoformat()],
        timeout=18,
    )
    totals = result.get("totals") if isinstance(result, dict) else None
    return totals if isinstance(totals, dict) else None


def _agent_metrics() -> dict[str, Any]:
    binary = shutil.which("agent-metrics")
    if not binary:
        return {"fallback_events": None, "reviews": None, "findings_accepted": None, "findings_total": None}
    report = _run([binary, "report"], timeout=8)
    fallback = re.search(r"Fallbacks:\s*(\d+) total", report)
    reviews = re.search(r"cross-vendor\s+(\d+) reviews,\s*(\d+)/(\d+) findings accepted", report)
    return {
        "fallback_events": int(fallback.group(1)) if fallback else None,
        "reviews": int(reviews.group(1)) if reviews else None,
        "findings_accepted": int(reviews.group(2)) if reviews else None,
        "findings_total": int(reviews.group(3)) if reviews else None,
    }


def _metric_used(metrics: dict[str, Any], key: str) -> float | None:
    value = metrics.get(key)
    if not isinstance(value, dict):
        return None
    return _numeric(value.get("used"))


def _openusage_activity() -> dict[str, dict[str, Any]]:
    binary = shutil.which("openusage")
    if not binary:
        return {}
    export = _run_json(
        [binary, "export", "--source", "direct", "--output", "-", "--format", "json"],
        timeout=24,
    )
    snapshots = export.get("snapshots", []) if isinstance(export, dict) else []
    if not isinstance(snapshots, list):
        return {}
    result: dict[str, dict[str, Any]] = {}
    for snapshot in snapshots:
        if not isinstance(snapshot, dict):
            continue
        provider_id = snapshot.get("provider_id")
        metrics = snapshot.get("metrics")
        if not isinstance(provider_id, str) or not isinstance(metrics, dict):
            continue
        activity: dict[str, Any] = {}
        if provider_id == "claude_code":
            for field, metric in (
                ("today_cost_usd", "today_api_cost"),
                ("today_input_tokens", "today_input_tokens"),
                ("today_output_tokens", "today_output_tokens"),
                ("seven_day_cost_usd", "7d_api_cost"),
                ("seven_day_input_tokens", "7d_input_tokens"),
                ("seven_day_output_tokens", "7d_output_tokens"),
            ):
                activity[field] = _metric_used(metrics, metric)
        elif provider_id == "openrouter":
            activity["today_cost_usd"] = _metric_used(metrics, "today_api_cost")
            activity["seven_day_cost_usd"] = _metric_used(metrics, "7d_api_cost")
        elif provider_id == "zai":
            activity["seven_day_tokens"] = _metric_used(metrics, "7d_tokens")
        if activity:
            result[provider_id] = activity
    return result


def _numeric(value: Any) -> float | None:
    if isinstance(value, bool):
        return None
    try:
        number = float(value)
    except (TypeError, ValueError, OverflowError):
        return None
    return number if math.isfinite(number) else None


def _format_reset(details: str, period: str) -> str | None:
    match = re.search(re.escape(period) + r" resets ([^(,]+) \(in ([^)]+)\)", details, re.IGNORECASE)
    return match.group(2) if match else None


def _reset_at(details: str, period: str) -> str | None:
    match = re.search(re.escape(period) + r" resets ([^(,]+)", details, re.IGNORECASE)
    return match.group(1).strip() if match else None


def _provider_payload(provider: dict[str, Any], provider_id: str) -> dict[str, Any]:
    details = str(provider.get("details") or "")
    five = _numeric(provider.get("five_hour_left"))
    seven = _numeric(provider.get("seven_day_left"))
    reset = provider.get("reset_available")
    if not isinstance(reset, (str, bool, int, float)):
        reset = None
    payload: dict[str, Any] = {
        "id": provider_id,
        "five_hour_left": five,
        "five_hour_reset": provider.get("five_hour_reset") if isinstance(provider.get("five_hour_reset"), str) else None,
        "five_hour_reset_in": _format_reset(details, "5h"),
        "five_hour_reset_at": _reset_at(details, "5h"),
        "seven_day_left": seven,
        "weekly_reset": provider.get("weekly_reset") if isinstance(provider.get("weekly_reset"), str) else None,
        "seven_day_reset_in": _format_reset(details, "7d"),
        "seven_day_reset_at": _reset_at(details, "7d"),
        "reset_available": reset,
        "remaining": _numeric(provider.get("remaining")),
        # Do not copy provider detail strings (which may contain account data)
        # into the dashboard snapshot. Only structured counters and resets pass.
    }
    if provider_id == "pi":
        tokens = re.search(r"([0-9,]+) total tokens", details)
        payload["total_tokens"] = int(tokens.group(1).replace(",", "")) if tokens else None
    if provider_id == "hermes":
        cost = re.search(r"\$([0-9]+(?:\.[0-9]+)?) used", details)
        payload["today_cost_usd"] = float(cost.group(1)) if cost else None
    return payload


def _read_local_observation() -> tuple[str, str, Any] | None:
    try:
        request = urllib.request.Request(LOCAL_URL + "/v1/models")
        with urllib.request.urlopen(request, timeout=4) as response:
            model_doc = json.loads(response.read(2_000_000))
        models = model_doc.get("data", []) if isinstance(model_doc, dict) else []
        model = str(models[0].get("id", "local model")) if models and isinstance(models[0], dict) else "local model"
    except (OSError, ValueError, urllib.error.URLError, TimeoutError):
        return None

    counters: dict[str, int] = {}
    try:
        request = urllib.request.Request(LOCAL_URL + "/metrics")
        with urllib.request.urlopen(request, timeout=4) as response:
            metrics = response.read(2_000_000).decode("utf-8", "replace")
        for line in metrics.splitlines():
            match = METRIC_LINE.fullmatch(line)
            if match:
                try:
                    counters[match.group(1)] = int(float(match.group(2)))
                except (ValueError, OverflowError):
                    pass
    except (OSError, urllib.error.URLError, TimeoutError, UnicodeError):
        pass
    if counters:
        return model[:160], "metrics", counters

    # /slots can contain prompt text. Keep its response in memory only and
    # extract just active request flags and numeric token counters.
    try:
        request = urllib.request.Request(LOCAL_URL + "/slots")
        with urllib.request.urlopen(request, timeout=4) as response:
            slots_doc = json.loads(response.read(2_000_000))
    except (OSError, ValueError, urllib.error.URLError, TimeoutError):
        return None
    if not isinstance(slots_doc, list):
        return None
    active = []
    for slot in slots_doc:
        if not isinstance(slot, dict) or slot.get("is_processing") is not True:
            continue
        counts = {}
        for field in ("n_prompt_tokens", "n_prompt_tokens_processed", "n_decoded", "n_tokens_predicted"):
            value = slot.get(field)
            if isinstance(value, (int, float)) and not isinstance(value, bool) and value >= 0:
                counts[field] = int(value)
        if counts:
            active.append((str(slot.get("id", "0")), str(slot.get("id_task", "0")), counts))
    return model[:160], "slots-input-only", active


def _read_state(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
        if isinstance(value, dict) and value.get("schema") == 1:
            return value
    except (OSError, UnicodeError, ValueError):
        pass
    return {"schema": 1, "total_tokens": 0, "daily": {}, "last_counters": {}}


def _write_state(path: Path, state: dict[str, Any]) -> None:
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(path.parent, 0o700)
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(state, separators=(",", ":")) + "\n", encoding="utf-8")
    os.chmod(temporary, 0o600)
    temporary.replace(path)


def _sample_local(seen_slots: dict[str, tuple[str, int]]) -> bool:
    observation = _read_local_observation()
    if observation is None:
        return False
    model, source, counts = observation
    path = _state_path()
    state = _read_state(path)
    delta = 0
    if source == "metrics":
        previous = state.get("last_counters", {})
        if not isinstance(previous, dict):
            previous = {}
        for name, current in counts.items():
            old = previous.get(name)
            delta += current if not isinstance(old, int) or current < old else current - old
        state["last_counters"] = counts
    else:
        for slot_id, task_id, values in counts:
            current = sum(values.values())
            previous = seen_slots.get(slot_id)
            if previous is None or previous[0] != task_id:
                delta += current
            elif current > previous[1]:
                delta += current - previous[1]
            seen_slots[slot_id] = (task_id, current)

    local_day = dt.datetime.now().astimezone().date().isoformat()
    daily = state.get("daily", {})
    if not isinstance(daily, dict):
        daily = {}
    if delta > 0:
        daily[local_day] = int(daily.get(local_day, 0) or 0) + delta
    state["total_tokens"] = int(state.get("total_tokens", 0) or 0) + delta
    state["daily"] = daily
    state["last"] = {
        "model": model,
        "source": source,
        "sampled_at": dt.datetime.now().astimezone().isoformat(),
    }
    _write_state(path, state)
    return True


def _collector_loop() -> int:
    path = _state_path()
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    lock_path = path.with_suffix(".lock")
    with lock_path.open("a", encoding="utf-8") as lock:
        os.chmod(lock_path, 0o600)
        try:
            fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return 0
        seen_slots: dict[str, tuple[str, int]] = {}
        while True:
            try:
                available = _sample_local(seen_slots)
            except (OSError, ValueError, TypeError):
                available = False
            time.sleep(LOCAL_INTERVAL if available else LOCAL_DOWN_INTERVAL)


def _local_summary(rate: float, today: dt.date) -> dict[str, Any]:
    state = _read_state(_state_path())
    daily = state.get("daily", {})
    if not isinstance(daily, dict):
        daily = {}
    monday = today - dt.timedelta(days=today.weekday())
    today_tokens = int(daily.get(today.isoformat(), 0) or 0)
    week_tokens = sum(int(value or 0) for day, value in daily.items() if monday.isoformat() <= day <= today.isoformat())
    total_tokens = int(state.get("total_tokens", 0) or 0)
    last = state.get("last", {})
    if not isinstance(last, dict):
        last = {}
    return {
        "model": last.get("model"),
        "source": last.get("source"),
        "today_tokens": today_tokens,
        "week_tokens": week_tokens,
        "total_tokens": total_tokens,
        "rate_usd_per_mtok": rate,
        "today_savings_estimate_usd": today_tokens * rate / 1_000_000,
        "week_savings_estimate_usd": week_tokens * rate / 1_000_000,
        "total_savings_estimate_usd": total_tokens * rate / 1_000_000,
        "estimate_note": "Estimate: /metrics counters when enabled; otherwise 1s /slots samples prompt tokens only, so short requests and output tokens can be missed.",
    }


def _snapshot() -> dict[str, Any]:
    now = dt.datetime.now().astimezone()
    today = now.date()
    monday = today - dt.timedelta(days=today.weekday())
    raw = _ai_usage()
    provider_activity = _openusage_activity()
    raw_providers = raw.get("providers", []) if isinstance(raw, dict) else []
    provider_map = {item.get("id"): item for item in raw_providers if isinstance(item, dict)}
    providers = [_provider_payload(provider_map.get(pid, {}), pid) for pid in PROVIDER_IDS]
    for provider in providers:
        provider["activity"] = provider_activity.get(provider["id"], {})
    providers.append({"id": "local", "five_hour_left": None, "seven_day_left": None, "reset_available": None})

    daily = _openusage_period("daily", today, today)
    weekly = _openusage_period("weekly", monday, today)
    try:
        raw_rate = float(os.environ.get("AI_USAGE_LOCAL_REFERENCE_USD_PER_MTOK", "0.20"))
        rate = max(0.0, raw_rate) if math.isfinite(raw_rate) else 0.20
    except (TypeError, ValueError):
        rate = 0.20

    return {
        "updated_at": now.isoformat(),
        "collector_state": str(raw.get("state")) if isinstance(raw, dict) else "unavailable",
        "providers": providers,
        "tracked_usage": {
            "today": {
                "tokens": int((daily or {}).get("total_tokens", 0) or 0),
                "cost_usd": _numeric((daily or {}).get("cost_usd")),
                "cost_method": "OpenUsage API-equivalent estimate",
            },
            "week": {
                "tokens": int((weekly or {}).get("total_tokens", 0) or 0),
                "cost_usd": _numeric((weekly or {}).get("cost_usd")),
                "cost_method": "OpenUsage API-equivalent estimate",
            },
        },
        "local_savings": _local_summary(rate, today),
        "workflow": _agent_metrics(),
    }


def main() -> int:
    if sys.argv[1:] == ["--collect-local"]:
        return _collector_loop()
    try:
        result = _snapshot()
        try:
            _persist_snapshot(result)
        except OSError:
            pass
        sys.stdout.write(json.dumps(result, separators=(",", ":"), ensure_ascii=False) + "\n")
        return 0
    except Exception:
        # The QML side gets one valid document even if an optional source fails.
        fallback = {"updated_at": dt.datetime.now().astimezone().isoformat(), "collector_state": "partial", "providers": [], "tracked_usage": {}, "local_savings": _local_summary(0.20, dt.date.today()), "workflow": {}}
        sys.stdout.write(json.dumps(fallback, separators=(",", ":"), ensure_ascii=False) + "\n")
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
