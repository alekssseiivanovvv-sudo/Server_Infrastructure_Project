#!/usr/bin/env python3
"""
Универсальный фикс дашбордов Grafana:
- Замена объектов datasource на строки
- Замена устаревших метрик Node Exporter
- Замена {service=~".+"} → {host=~".+"}
- Уборка :.* после instance
- Фиксация UID и id=null
"""
import json
import re
import sys
import glob
import os

STRING_REPLACEMENTS = {
    # Node Exporter
    "node_cpu{": "node_cpu_seconds_total{",
    "node_boot_time{": "node_boot_time_seconds{",
    "node_time{": "node_time_seconds{",
    "node_memory_MemTotal{": "node_memory_MemTotal_bytes{",
    "node_memory_MemFree{": "node_memory_MemFree_bytes{",
    "node_memory_MemAvailable{": "node_memory_MemAvailable_bytes{",
    "node_memory_Buffers{": "node_memory_Buffers_bytes{",
    "node_memory_Cached{": "node_memory_Cached_bytes{",
    "node_memory_SwapTotal{": "node_memory_SwapTotal_bytes{",
    "node_memory_SwapFree{": "node_memory_SwapFree_bytes{",
    "node_filesystem_size{": "node_filesystem_size_bytes{",
    "node_filesystem_avail{": "node_filesystem_avail_bytes{",
    "node_filesystem_free{": "node_filesystem_free_bytes{",
    "node_network_receive_bytes{": "node_network_receive_bytes_total{",
    "node_network_transmit_bytes{": "node_network_transmit_bytes_total{",
    "node_disk_read_bytes{": "node_disk_read_bytes_total{",
    "node_disk_written_bytes{": "node_disk_written_bytes_total{",
    # Job
    'job="node-exporter"': 'job="integrations/unix"',
    # Loki
    '{job="varlogs"}': '{host=~".+"}',
    '{job="docker"}': '{host=~".+"}',
    '{job="syslog"}': '{host=~".+"}',
    '{service=~".+"}': '{host=~".+"}',
}

REGEX_REPLACEMENTS = [
    (re.compile(r'instance=~"([^":]+):\.\*"'), r'instance=~"\1"'),
    (re.compile(r"instance=~'([^':]+):\.\*'"), r"instance=~'\1'"),
    (re.compile(r'\{service\s*=~\s*\\?"[^"\\]*\\?"\}'), '{host=~\\".+\\"}'),
]


def fix_datasources(obj):
    if isinstance(obj, dict):
        ds = obj.get("datasource")
        if isinstance(ds, dict) and "type" in ds:
            if ds["type"] == "prometheus":
                obj["datasource"] = "Prometheus"
            elif ds["type"] == "loki":
                obj["datasource"] = "Loki"
        for v in obj.values():
            fix_datasources(v)
    elif isinstance(obj, list):
        for item in obj:
            fix_datasources(item)


def fix_strings(obj):
    if isinstance(obj, dict):
        for k, v in obj.items():
            if isinstance(v, str):
                for old, new in STRING_REPLACEMENTS.items():
                    v = v.replace(old, new)
                for pattern, repl in REGEX_REPLACEMENTS:
                    v = pattern.sub(repl, v)
                obj[k] = v
            else:
                fix_strings(v)
    elif isinstance(obj, list):
        for i, item in enumerate(obj):
            if isinstance(item, str):
                for old, new in STRING_REPLACEMENTS.items():
                    item = item.replace(old, new)
                for pattern, repl in REGEX_REPLACEMENTS:
                    item = pattern.sub(repl, item)
                obj[i] = item
            else:
                fix_strings(item)


def process_file(path):
    try:
        with open(path) as f:
            d = json.load(f)
    except json.JSONDecodeError as e:
        print(f"[SKIP] {path}: {e}")
        return False

    fix_datasources(d)
    fix_strings(d)

    d["uid"] = os.path.splitext(os.path.basename(path))[0]
    d["id"] = None

    with open(path, "w") as f:
        json.dump(d, f, indent=2, ensure_ascii=False)

    print(f"[OK] {path}")
    return True


def main():
    if len(sys.argv) < 2:
        print("Usage: fix_dashboards.py <dashboards_dir>")
        sys.exit(1)

    dashboards_dir = sys.argv[1]
    changed = 0

    for path in glob.glob(os.path.join(dashboards_dir, "*.json")):
        if process_file(path):
            changed += 1

    print(f"Processed {changed} files")


if __name__ == "__main__":
    main()
