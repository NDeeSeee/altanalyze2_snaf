#!/usr/bin/env python3
import argparse
import json
import os
from datetime import datetime
from statistics import mean
from typing import Any, Dict, List, Optional

FIELDS_NUMERIC = [
    "load1",
    "mem_used_mb",
    "mem_free_mb",
    "disk_used_gb",
    "disk_free_gb",
    "disk_used_gb_root",
    "disk_free_gb_root",
    "disk_used_gb_pwd",
    "disk_free_gb_pwd",
    "alt_cpu",
    "alt_pmem",
    "alt_rss_mb",
    "alt_vsz_mb",
    "alt_read_mb",
    "alt_write_mb",
    # Optional IO rates
    "disk_read_mb_s",
    "disk_write_mb_s",
    "net_recv_mb_s",
    "net_sent_mb_s",
]


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Aggregate resource-monitor JSONL into summary metrics.")
    p.add_argument("monitor_dir", help="Directory containing usage.jsonl and metadata.json")
    p.add_argument("--out-json", default=None, help="Path to write summary JSON (default: monitor_dir/summary.metrics.json)")
    p.add_argument("--out-tsv", default=None, help="Path to write summary TSV (default: monitor_dir/summary.metrics.tsv)")
    return p.parse_args()


def parse_time(ts: str) -> Optional[datetime]:
    try:
        # Accept both with/without Z
        if ts.endswith("Z"):
            ts = ts[:-1]
        return datetime.fromisoformat(ts)
    except Exception:
        return None


def aggregate(records: List[Dict[str, Any]]) -> Dict[str, Any]:
    if not records:
        return {"count": 0}

    # time span
    t0 = parse_time(records[0].get("ts", ""))
    t1 = parse_time(records[-1].get("ts", ""))
    duration_s = (t1 - t0).total_seconds() if (t0 and t1) else None

    # Task context (take last non-empty)
    task = next((r.get("task") for r in reversed(records) if r.get("task")), "")
    shard = next((r.get("shard") for r in reversed(records) if r.get("shard")), "")
    attempt = next((r.get("attempt") for r in reversed(records) if r.get("attempt")), "")

    # Numeric aggregates
    agg: Dict[str, Dict[str, Optional[float]]] = {}
    for key in FIELDS_NUMERIC:
        vals = [r.get(key) for r in records if isinstance(r.get(key), (int, float))]
        if vals:
            agg[key] = {
                "min": float(min(vals)),
                "max": float(max(vals)),
                "avg": float(mean(vals)),
            }
        else:
            agg[key] = {"min": None, "max": None, "avg": None}

    # Low disk events
    low_disk_warn = [r for r in records if isinstance(r.get("disk_free_gb"), (int, float)) and r["disk_free_gb"] <= 20]
    low_disk_crit = [r for r in records if isinstance(r.get("disk_free_gb"), (int, float)) and r["disk_free_gb"] <= 5]

    # High-water mark for AltAnalyze RSS
    alt_hwm_rss_mb = agg["alt_rss_mb"]["max"]

    return {
        "task": task,
        "shard": shard,
        "attempt": attempt,
        "count": len(records),
        "start_ts": records[0].get("ts"),
        "end_ts": records[-1].get("ts"),
        "duration_s": duration_s,
        "metrics": agg,
        "events": {
            "low_disk_warn_count": len(low_disk_warn),
            "low_disk_crit_count": len(low_disk_crit),
            "min_disk_free_gb": agg["disk_free_gb"]["min"],
            "alt_hwm_rss_mb": alt_hwm_rss_mb,
        },
    }


def write_tsv(summary: Dict[str, Any], path: str) -> None:
    # Flatten key metrics into a small TSV row
    hdr = [
        "task","shard","attempt","count","duration_s",
        "load1_avg","mem_used_mb_max","disk_free_gb_min","alt_rss_mb_max",
        "disk_read_mb_s_avg","disk_write_mb_s_avg","net_recv_mb_s_avg","net_sent_mb_s_avg",
        "low_disk_warn_count","low_disk_crit_count",
    ]
    m = summary.get("metrics", {})
    ev = summary.get("events", {})
    row = [
        summary.get("task",""),
        summary.get("shard",""),
        summary.get("attempt",""),
        str(summary.get("count",0)),
        str(summary.get("duration_s","")),
        str((m.get("load1") or {}).get("avg","")),
        str((m.get("mem_used_mb") or {}).get("max","")),
        str((m.get("disk_free_gb") or {}).get("min","")),
        str((m.get("alt_rss_mb") or {}).get("max","")),
        str((m.get("disk_read_mb_s") or {}).get("avg","")),
        str((m.get("disk_write_mb_s") or {}).get("avg","")),
        str((m.get("net_recv_mb_s") or {}).get("avg","")),
        str((m.get("net_sent_mb_s") or {}).get("avg","")),
        str(ev.get("low_disk_warn_count","")),
        str(ev.get("low_disk_crit_count","")),
    ]
    with open(path, "w") as f:
        f.write("\t".join(hdr)+"\n")
        f.write("\t".join(row)+"\n")


def main() -> None:
    args = parse_args()
    mon_dir = args.monitor_dir
    jsonl_path = os.path.join(mon_dir, "usage.jsonl")
    meta_path = os.path.join(mon_dir, "metadata.json")
    if not os.path.exists(jsonl_path):
        raise SystemExit(f"Not found: {jsonl_path}")

    records: List[Dict[str, Any]] = []
    with open(jsonl_path, "r") as f:
        for line in f:
            try:
                obj = json.loads(line)
                records.append(obj)
            except Exception:
                continue
    if not records:
        raise SystemExit("No records parsed from usage.jsonl")

    summary = aggregate(records)

    out_json = args.out_json or os.path.join(mon_dir, "summary.metrics.json")
    with open(out_json, "w") as f:
        json.dump(summary, f, indent=2)

    out_tsv = args.out_tsv or os.path.join(mon_dir, "summary.metrics.tsv")
    write_tsv(summary, out_tsv)

    # Copy over metadata for convenience
    try:
        if os.path.exists(meta_path):
            with open(meta_path, "r") as f:
                meta = json.load(f)
            wrapper = {"metadata": meta, "summary": summary}
            with open(out_json, "w") as f:
                json.dump(wrapper, f, indent=2)
    except Exception:
        pass

    print(f"Wrote {out_json} and {out_tsv}")


if __name__ == "__main__":
    main()
