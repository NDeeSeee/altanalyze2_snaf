#!/usr/bin/env python3
import json
import os
import sys
import time
import socket
from datetime import datetime

# Optional psutil for richer metrics
try:
    import psutil  # type: ignore
except Exception:
    psutil = None

MON_DIR = os.environ.get("MON_DIR", "/cromwell_root/monitoring")
INTERVAL = int(os.environ.get("MONITOR_INTERVAL_SECONDS", "15"))
HEAVY_INTERVAL = int(os.environ.get("MONITOR_HEAVY_INTERVAL_SECONDS", "60"))
LOW_DISK_GB_WARN = float(os.environ.get("LOW_DISK_GB_WARN", "20"))
LOW_DISK_GB_CRIT = float(os.environ.get("LOW_DISK_GB_CRIT", "5"))
LIGHT_MODE = int(os.environ.get("MON_LIGHT", "0"))
MAX_SAMPLES = int(os.environ.get("MON_MAX_SAMPLES", "0"))

os.makedirs(MON_DIR, exist_ok=True)
OUT_TSV = os.path.join(MON_DIR, "usage.tsv")
OUT_JSONL = os.path.join(MON_DIR, "usage.jsonl")
TOP_TXT = os.path.join(MON_DIR, "top.txt")
LARGEST_TXT = os.path.join(MON_DIR, "largest.txt")
SUMMARY_TXT = os.path.join(MON_DIR, "summary.txt")
SAMPLE_NAME_FILE = os.path.join(MON_DIR, "sample_name.txt")
META_JSON = os.path.join(MON_DIR, "metadata.json")

START_TIME = time.time()

CR_ROOT = "/mnt/disks/cromwell_root"
if not os.path.ismount(CR_ROOT):
    if os.path.exists("/cromwell_root"):
        CR_ROOT = "/cromwell_root"
    else:
        CR_ROOT = os.getcwd()


def write_summary():
    try:
        with open(OUT_TSV, "r") as f:
            lines = f.readlines()
        latest = lines[-1].strip() if lines else ""
    except Exception:
        latest = ""
    try:
        with open(LARGEST_TXT, "r") as f:
            topdisk = "".join(f.readlines()[:50])
    except Exception:
        topdisk = ""
    with open(SUMMARY_TXT, "w") as f:
        print(f"Monitoring summary at {datetime.utcnow().isoformat()}Z", file=f)
        print("Latest usage line:", file=f)
        print(latest, file=f)
        print("Top disk users (last sample):", file=f)
        f.write(topdisk)


def detect_task_context():
    cwd = os.getcwd()
    call = shard = attempt = ""
    parts = cwd.split("/")
    for i, p in enumerate(parts):
        if p.startswith("call-"):
            call = p[len("call-"):]
        elif p.startswith("shard-"):
            shard = p[len("shard-"):]
        elif p.startswith("attempt-"):
            attempt = p[len("attempt-"):]
    return call, shard, attempt, cwd


def read_cgroup_limits():
    cpu_limit = None
    mem_limit = None
    mem_current = None
    try:
        # cgroup v2
        if os.path.exists("/sys/fs/cgroup/cpu.max"):
            with open("/sys/fs/cgroup/cpu.max", "r") as f:
                parts = f.read().strip().split()
            if len(parts) == 2 and parts[0].isdigit() and parts[1].isdigit():
                quota = float(parts[0])
                period = float(parts[1])
                if period > 0:
                    cpu_limit = round(quota / period, 2)
        elif os.path.exists("/sys/fs/cgroup/cpu/cpu.cfs_quota_us") and os.path.exists("/sys/fs/cgroup/cpu/cpu.cfs_period_us"):
            with open("/sys/fs/cgroup/cpu/cpu.cfs_quota_us", "r") as f:
                quota = float(f.read().strip())
            with open("/sys/fs/cgroup/cpu/cpu.cfs_period_us", "r") as f:
                period = float(f.read().strip())
            if quota > 0 and period > 0:
                cpu_limit = round(quota / period, 2)
    except Exception:
        pass
    try:
        if os.path.exists("/sys/fs/cgroup/memory.max"):
            with open("/sys/fs/cgroup/memory.max", "r") as f:
                mx = f.read().strip()
            with open("/sys/fs/cgroup/memory.current", "r") as f:
                cur = f.read().strip()
            if mx != "max" and mx.isdigit():
                mem_limit = round(int(mx) / 1024 / 1024, 1)
            if cur.isdigit():
                mem_current = round(int(cur) / 1024 / 1024, 1)
        elif os.path.exists("/sys/fs/cgroup/memory/memory.limit_in_bytes"):
            with open("/sys/fs/cgroup/memory/memory.limit_in_bytes", "r") as f:
                mx = f.read().strip()
            with open("/sys/fs/cgroup/memory/memory.usage_in_bytes", "r") as f:
                cur = f.read().strip()
            if mx.isdigit():
                mem_limit = round(int(mx) / 1024 / 1024, 1)
            if cur.isdigit():
                mem_current = round(int(cur) / 1024 / 1024, 1)
    except Exception:
        pass
    return cpu_limit, mem_limit, mem_current


# Initialize TSV header
if not os.path.exists(OUT_TSV):
    with open(OUT_TSV, "w") as f:
        f.write("\t".join([
            "timestamp","load1","mem_used_mb","mem_free_mb",
            "disk_used_gb","disk_free_gb","disk_used_gb_root","disk_free_gb_root",
            "disk_used_gb_pwd","disk_free_gb_pwd"
        ]) + "\n")

# Write metadata once
call, shard, attempt, cwd = detect_task_context()
cl_cpu, cl_mem, cl_mem_cur = read_cgroup_limits()
meta = {
    "ts": datetime.now().isoformat(),
    "hostname": socket.gethostname(),
    "task": call, "shard": shard, "attempt": attempt, "cwd": cwd,
    "cpu_limit_cores": cl_cpu, "mem_limit_mb": cl_mem, "mem_current_mb": cl_mem_cur,
    "cpu_count": psutil.cpu_count() if psutil else None,
    "env_sample": f"MON_DIR={MON_DIR};INTERVAL={INTERVAL};HEAVY_INTERVAL={HEAVY_INTERVAL};LOW_DISK_GB_WARN={LOW_DISK_GB_WARN};LOW_DISK_GB_CRIT={LOW_DISK_GB_CRIT};LIGHT_MODE={LIGHT_MODE}",
}
try:
    with open(META_JSON, "w") as f:
        f.write(json.dumps(meta) + "\n")
except Exception:
    pass

sample = 0
try:
    while True:
        ts = datetime.now().isoformat()
        # CPU load and memory
        load1 = 0.0
        mem_used_mb = mem_free_mb = 0
        try:
            if psutil:
                load1 = psutil.getloadavg()[0]
                vm = psutil.virtual_memory()
                mem_used_mb = round((vm.total - vm.available) / 1024 / 1024)
                mem_free_mb = round(vm.available / 1024 / 1024)
        except Exception:
            pass
        # Disks
        def df_path(path: str):
            try:
                st = os.statvfs(path)
                used = (st.f_blocks - st.f_bfree) * st.f_frsize
                free = st.f_bavail * st.f_frsize
                return round(used / 1024 / 1024 / 1024, 1), round(free / 1024 / 1024 / 1024, 1)
            except Exception:
                return 0.0, 0.0
        disk_used_gb, disk_free_gb = df_path(CR_ROOT)
        disk_used_gb_root, disk_free_gb_root = df_path("/")
        disk_used_gb_pwd, disk_free_gb_pwd = df_path(".")

        # Optional sample_name
        if not os.path.exists(SAMPLE_NAME_FILE):
            try:
                bamdir = "/mnt/bam"
                if os.path.isdir(bamdir):
                    for fn in os.listdir(bamdir):
                        if fn.endswith(".bam"):
                            with open(SAMPLE_NAME_FILE, "w") as f:
                                f.write(fn)
                            break
            except Exception:
                pass
        try:
            with open(SAMPLE_NAME_FILE, "r") as f:
                sample_name = f.read().strip()
        except Exception:
            sample_name = ""

        # AltAnalyze process metrics (best-effort)
        alt = {"pid": None, "cpu": None, "pmem": None, "rss_mb": None, "vsz_mb": None, "read_mb": None, "write_mb": None}
        if psutil:
            try:
                procs = []
                for p in psutil.process_iter(attrs=["pid","name","cmdline","cpu_percent","memory_percent","memory_info","io_counters"]):
                    cmd = " ".join(p.info.get("cmdline") or [])
                    name = p.info.get("name") or ""
                    if "AltAnalyze.sh" in cmd or "AltAnalyze.py" in cmd or "bam_to_bed" in cmd or name.startswith("AltAnalyze"):
                        procs.append(p)
                if procs:
                    # Pick highest CPU
                    procs.sort(key=lambda x: x.info.get("cpu_percent") or 0.0, reverse=True)
                    p = procs[0]
                    mi = p.info.get("memory_info")
                    io = p.info.get("io_counters")
                    alt = {
                        "pid": p.info.get("pid"),
                        "cpu": p.info.get("cpu_percent"),
                        "pmem": p.info.get("memory_percent"),
                        "rss_mb": round((mi.rss if mi else 0)/1024/1024, 1),
                        "vsz_mb": round((mi.vms if mi else 0)/1024/1024, 1),
                        "read_mb": round((io.read_bytes if io else 0)/1024/1024, 1),
                        "write_mb": round((io.write_bytes if io else 0)/1024/1024, 1),
                    }
            except Exception:
                pass

        # Emit TSV line
        with open(OUT_TSV, "a") as f:
            f.write("\t".join(map(str, [
                ts, load1, mem_used_mb, mem_free_mb,
                disk_used_gb, disk_free_gb, disk_used_gb_root, disk_free_gb_root,
                disk_used_gb_pwd, disk_free_gb_pwd
            ])) + "\n")

        # Emit JSON line
        record = {
            "ts": ts, "mon_secs": int(time.time() - START_TIME),
            "task": call, "shard": shard, "attempt": attempt, "cwd": cwd,
            "sample": sample_name,
            "load1": load1, "mem_used_mb": mem_used_mb, "mem_free_mb": mem_free_mb,
            "disk_used_gb": disk_used_gb, "disk_free_gb": disk_free_gb,
            "disk_used_gb_root": disk_used_gb_root, "disk_free_gb_root": disk_free_gb_root,
            "disk_used_gb_pwd": disk_used_gb_pwd, "disk_free_gb_pwd": disk_free_gb_pwd,
            "alt_pid": alt["pid"], "alt_cpu": alt["cpu"], "alt_pmem": alt["pmem"],
            "alt_rss_mb": alt["rss_mb"], "alt_vsz_mb": alt["vsz_mb"],
            "alt_read_mb": alt["read_mb"], "alt_write_mb": alt["write_mb"],
        }
        with open(OUT_JSONL, "a") as f:
            f.write(json.dumps(record) + "\n")

        # top snapshots (limited)
        if psutil:
            try:
                procs = list(psutil.process_iter(attrs=["pid","cpu_percent","memory_percent","name","cmdline","memory_info"]))
                top_cpu = sorted(procs, key=lambda p: p.info.get("cpu_percent") or 0.0, reverse=True)[:30]
                top_rss = sorted(procs, key=lambda p: (p.info.get("memory_info").rss if p.info.get("memory_info") else 0), reverse=True)[:30]
                with open(TOP_TXT, "w") as f:
                    print(f"[{ts}] top by CPU:", file=f)
                    for p in top_cpu:
                        cmd = " ".join(p.info.get("cmdline") or [])
                        mi = p.info.get("memory_info")
                        print(f"{p.info.get('pid')} {p.info.get('cpu_percent')}% {p.info.get('memory_percent'):.2f}% {mi.rss/1024/1024 if mi else 0:.1f}MB {p.info.get('name')} {cmd}", file=f)
                    print("\n", file=f)
                    print(f"[{ts}] top by RSS:", file=f)
                    for p in top_rss:
                        cmd = " ".join(p.info.get("cmdline") or [])
                        mi = p.info.get("memory_info")
                        print(f"{p.info.get('pid')} {mi.rss/1024/1024 if mi else 0:.1f}MB {p.info.get('cpu_percent')}% {p.info.get('memory_percent'):.2f}% {p.info.get('name')} {cmd}", file=f)
            except Exception:
                pass
        # heavy sampling
        do_heavy = False
        if LIGHT_MODE == 0:
            # time-based cadence
            try:
                if int(time.time()) % HEAVY_INTERVAL < INTERVAL:
                    do_heavy = True
            except Exception:
                pass
            # low disk
            try:
                if float(disk_free_gb) <= LOW_DISK_GB_WARN:
                    do_heavy = True
            except Exception:
                pass
        if do_heavy:
            try:
                # limited and simple to avoid large overheads
                key_dirs = [CR_ROOT, os.environ.get("TMPDIR", "/tmp"), "/mnt/bam", "/mnt/altanalyze_output", "/cromwell_root"]
                lines = [f"[{ts}] du -sk key dirs (MB):\n"]
                for d in key_dirs:
                    try:
                        st = os.statvfs(d)
                        used_mb = int(((st.f_blocks - st.f_bfree) * st.f_frsize) / 1024 / 1024)
                        lines.append(f"{used_mb:10d} MB\t{d}\n")
                    except Exception:
                        pass
                lines.append(f"[{ts}] largest files under {CR_ROOT}:\n")
                # Avoid expensive recursive walks: cap files and depth
                largest = []
                for root, dirs, files in os.walk(CR_ROOT):
                    # do not cross filesystem boundaries and limit traversal
                    if len(root.split(os.sep)) - len(CR_ROOT.split(os.sep)) > 3:
                        dirs[:] = []
                        continue
                    for fn in files:
                        try:
                            p = os.path.join(root, fn)
                            st = os.stat(p)
                            largest.append((st.st_size, p))
                        except Exception:
                            pass
                    if len(largest) > 5000:
                        break
                largest.sort(reverse=True)
                lines.extend([f"{sz/1024/1024:8.1f} MB {path}\n" for sz, path in largest[:50]])
                with open(LARGEST_TXT, "w") as f:
                    f.writelines(lines)
            except Exception:
                pass

        # adaptive sleep
        next_sleep = INTERVAL
        try:
            if float(disk_free_gb) <= LOW_DISK_GB_CRIT:
                print(f"[{ts}] CRITICAL: low disk ({disk_free_gb} GB free)", file=sys.stderr)
                next_sleep = 5
            elif float(disk_free_gb) <= LOW_DISK_GB_WARN:
                print(f"[{ts}] WARNING: low disk ({disk_free_gb} GB free)", file=sys.stderr)
                next_sleep = INTERVAL
        except Exception:
            pass

        sample += 1
        if MAX_SAMPLES > 0 and sample >= MAX_SAMPLES:
            write_summary()
            break
        time.sleep(next_sleep)
except KeyboardInterrupt:
    pass
finally:
    write_summary()
