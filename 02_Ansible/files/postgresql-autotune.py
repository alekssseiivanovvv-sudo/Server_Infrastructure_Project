#!/usr/bin/env python3
"""Generate conservative PostgreSQL settings from the server hardware.

The generated file is intended to be referenced by Patroni through
``postgresql.custom_conf``. Replication-critical settings are deliberately
left to Patroni's cluster-wide dynamic configuration.
"""

from __future__ import annotations

import argparse
import grp
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


MIB = 1024 * 1024


def clamp(value: int, minimum: int, maximum: int) -> int:
    return max(minimum, min(value, maximum))


def round_down(value: int, step: int) -> int:
    return max(step, value // step * step)


def detected_memory_mib() -> int:
    with open("/proc/meminfo", encoding="utf-8") as meminfo:
        for line in meminfo:
            if line.startswith("MemTotal:"):
                return int(line.split()[1]) // 1024
    raise RuntimeError("MemTotal was not found in /proc/meminfo")


def detected_cpu_count() -> int:
    return os.cpu_count() or 1


def detected_filesystem_mib(data_dir: Path) -> int:
    probe = data_dir
    while not probe.exists() and probe != probe.parent:
        probe = probe.parent
    return shutil.disk_usage(probe).total // MIB


def detect_storage_type(data_dir: Path) -> str:
    """Return ssd, hdd, or unknown from the block-device rotational flag."""
    try:
        source = subprocess.run(
            ["findmnt", "-n", "-o", "SOURCE", "-T", str(data_dir)],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()
        if not source.startswith("/dev/"):
            return "unknown"

        output = subprocess.run(
            ["lsblk", "-nro", "ROTA", source],
            check=True,
            capture_output=True,
            text=True,
        ).stdout
        flags = {line.strip() for line in output.splitlines() if line.strip()}
        if "1" in flags:
            return "hdd"
        if flags and flags == {"0"}:
            return "ssd"
    except (FileNotFoundError, subprocess.CalledProcessError):
        pass
    return "unknown"


def calculate(
    memory_mib: int,
    cpu_count: int,
    filesystem_mib: int,
    storage_type: str,
    max_connections: int,
) -> dict[str, str | int | float]:
    if memory_mib < 768:
        raise ValueError("at least 768 MiB RAM is required for this profile")
    if cpu_count < 1:
        raise ValueError("CPU count must be at least 1")
    if max_connections < 10:
        raise ValueError("max_connections must be at least 10")

    # The database VMs also run Patroni and etcd, so memory allocation stays
    # conservative and leaves room for the OS page cache and maintenance work.
    shared_buffers = round_down(max(128, memory_mib * 25 // 100), 8)
    effective_cache_size = round_down(max(128, memory_mib * 70 // 100), 8)
    maintenance_work_mem = round_down(clamp(memory_mib // 16, 64, 1024), 16)
    autovacuum_work_mem = round_down(clamp(memory_mib // 32, 64, 256), 16)

    # work_mem is allocated per sort/hash operation. Reserve memory for the OS,
    # shared buffers, one maintenance operation, and three autovacuum workers.
    os_reserve = max(512, memory_mib * 20 // 100)
    query_budget = max(
        0,
        memory_mib
        - os_reserve
        - shared_buffers
        - maintenance_work_mem
        - 3 * autovacuum_work_mem,
    )
    work_mem = clamp(query_budget // (max_connections * 3), 4, 64)

    # Keep WAL bounded on small lab filesystems: 10% of the filesystem, rounded
    # to 64 MiB and capped between 512 MiB and 4 GiB.
    max_wal_size = round_down(
        clamp(max(1, filesystem_mib) * 10 // 100, 512, 4096), 64
    )
    min_wal_size = round_down(max(128, max_wal_size // 4), 32)

    if storage_type == "ssd":
        random_page_cost = 1.1
        effective_io_concurrency = 64
        maintenance_io_concurrency = 32
    elif storage_type == "hdd":
        random_page_cost = 4.0
        effective_io_concurrency = 2
        maintenance_io_concurrency = 2
    else:
        random_page_cost = 2.5
        effective_io_concurrency = 16
        maintenance_io_concurrency = 16

    if cpu_count == 1:
        max_parallel_workers = 0
        max_parallel_workers_per_gather = 0
        max_parallel_maintenance_workers = 0
    else:
        max_parallel_workers = min(cpu_count, 8)
        max_parallel_workers_per_gather = min(max(1, cpu_count // 2), 4)
        max_parallel_maintenance_workers = min(max(1, cpu_count // 2), 4)

    return {
        "shared_buffers": f"{shared_buffers}MB",
        "effective_cache_size": f"{effective_cache_size}MB",
        "work_mem": f"{work_mem}MB",
        "maintenance_work_mem": f"{maintenance_work_mem}MB",
        "autovacuum_work_mem": f"{autovacuum_work_mem}MB",
        "huge_pages": "try",
        "effective_io_concurrency": effective_io_concurrency,
        "maintenance_io_concurrency": maintenance_io_concurrency,
        "random_page_cost": random_page_cost,
        "max_parallel_workers": max_parallel_workers,
        "max_parallel_workers_per_gather": max_parallel_workers_per_gather,
        "max_parallel_maintenance_workers": max_parallel_maintenance_workers,
        "checkpoint_completion_target": 0.9,
        "checkpoint_timeout": "15min",
        "max_wal_size": f"{max_wal_size}MB",
        "min_wal_size": f"{min_wal_size}MB",
    }


def render(
    settings: dict[str, str | int | float],
    memory_mib: int,
    cpu_count: int,
    filesystem_mib: int,
    storage_type: str,
    max_connections: int,
) -> str:
    lines = [
        "# Managed by project-postgresql-autotune. Manual changes will be replaced.",
        f"# Detected RAM: {memory_mib} MiB; CPUs: {cpu_count}; "
        f"filesystem: {filesystem_mib} MiB; storage: {storage_type}.",
        f"# work_mem calculation assumes max_connections = {max_connections}.",
        "",
    ]
    for key, value in settings.items():
        if isinstance(value, str):
            lines.append(f"{key} = '{value}'")
        else:
            lines.append(f"{key} = {value}")
    return "\n".join(lines) + "\n"


def atomic_write(output: Path, content: str) -> bool:
    existing = output.read_text(encoding="utf-8") if output.exists() else None
    if existing == content:
        return False

    output.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        dir=output.parent, prefix=f".{output.name}.", text=True
    )
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary, 0o640)
        if os.geteuid() == 0:
            try:
                os.chown(temporary, 0, grp.getgrnam("postgres").gr_gid)
            except KeyError:
                pass
        os.replace(temporary, output)
    finally:
        temporary.unlink(missing_ok=True)
    return True


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("/etc/patroni/postgresql-tuning.conf"),
    )
    parser.add_argument(
        "--data-dir", type=Path, default=Path("/var/lib/postgresql")
    )
    parser.add_argument("--storage", choices=("auto", "ssd", "hdd"), default="auto")
    parser.add_argument("--max-connections", type=int, default=100)
    parser.add_argument("--memory-mib", type=int, help=argparse.SUPPRESS)
    parser.add_argument("--cpus", type=int, help=argparse.SUPPRESS)
    parser.add_argument("--filesystem-mib", type=int, help=argparse.SUPPRESS)
    parser.add_argument(
        "--dry-run", action="store_true", help="print configuration without writing"
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    memory_mib = args.memory_mib or detected_memory_mib()
    cpu_count = args.cpus or detected_cpu_count()
    filesystem_mib = args.filesystem_mib or detected_filesystem_mib(args.data_dir)
    storage_type = (
        detect_storage_type(args.data_dir) if args.storage == "auto" else args.storage
    )
    settings = calculate(
        memory_mib,
        cpu_count,
        filesystem_mib,
        storage_type,
        args.max_connections,
    )
    content = render(
        settings,
        memory_mib,
        cpu_count,
        filesystem_mib,
        storage_type,
        args.max_connections,
    )

    if args.dry_run:
        print(content, end="")
        return 0
    if os.geteuid() != 0:
        print("error: writing the tuning file requires root", file=sys.stderr)
        return 1

    changed = atomic_write(args.output, content)
    print(f"{'updated' if changed else 'unchanged'}: {args.output}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1)
