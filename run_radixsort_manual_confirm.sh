#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VULKAN_RS_DIR="$ROOT_DIR/benchmark_repos/vulkan_radix_sort"
VULKAN_BUILD_DIR="$VULKAN_RS_DIR/build_embree_cuda"
VKRS_DIR="$ROOT_DIR/benchmark_repos/VkRadixSort"
VKRS_BUILD_DIR="$VKRS_DIR/build"
VKRS_HEADER="$VKRS_DIR/multiradixsort/include/MultiRadixSort.h"
VKRS_EXE="$VKRS_BUILD_DIR/multiradixsort/multiradixsortexample"

SIZES_CSV="${SIZES_CSV:-1048576,1572864,2097152,3145728,4194304}"
VKRS_RUNS="${VKRS_RUNS:-10}"
OUT_DIR="${OUT_DIR:-$ROOT_DIR/benchmark_results/manual_confirm_$(date +%Y%m%d_%H%M%S)}"

confirm() {
  local prompt="$1"
  local answer
  printf '\n%s [y/N] ' "$prompt"
  read -r answer
  case "$answer" in
    y|Y|yes|YES) return 0 ;;
    *) echo "Skip: $prompt"; return 1 ;;
  esac
}

require_file() {
  local path="$1"
  if [[ ! -e "$path" ]]; then
    echo "Missing required path: $path" >&2
    exit 1
  fi
}

show_gpu_load() {
  if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi --query-gpu=name,driver_version,utilization.gpu --format=csv,noheader,nounits || true
  else
    echo "nvidia-smi not found"
  fi
}

write_summary() {
  python3 - "$OUT_DIR" <<'PY'
import csv
import pathlib
import statistics
import sys

out_dir = pathlib.Path(sys.argv[1])
paths = {
    "jaesung": out_dir / "vulkan.csv",
    "embree": out_dir / "embree_cuda.csv",
    "vkr": out_dir / "vkradixsort_multi.csv",
}

summary_md = out_dir / "summary.md"
summary_csv = out_dir / "summary.csv"

jaesung = {}
embree = {}
for name, target in (("jaesung", jaesung), ("embree", embree)):
    if not paths[name].exists():
        continue
    with paths[name].open() as f:
        rows = csv.DictReader(line for line in f if not line.startswith("#"))
        for row in rows:
            target[(int(row["n"]), row["sort"])] = float(row["gpu_ms"])

vkr = {}
vkr_dist = {}
if paths["vkr"].exists():
    with paths["vkr"].open() as f:
        rows = list(csv.DictReader(f))
    for n in sorted({int(r["n"]) for r in rows}):
        vals = sorted(float(r["gpu_timestamp_sum_ms"]) for r in rows if int(r["n"]) == n)
        vkr[n] = statistics.median(vals)
        vkr_dist[n] = (min(vals), statistics.median(vals), max(vals))

sizes = sorted({n for n, sort in jaesung} | {n for n, sort in embree} | set(vkr))

with summary_csv.open("w", newline="") as f:
    fieldnames = ["n", "jaesung_keys_ms", "embree_keys_ms", "vkr_keys_p50_ms", "winner_keys", "jaesung_kv_ms", "embree_kv_ms", "winner_kv"]
    writer = csv.DictWriter(f, fieldnames=fieldnames)
    writer.writeheader()
    for n in sizes:
        keys = {}
        if (n, "keys") in jaesung:
            keys["jaesung"] = jaesung[(n, "keys")]
        if (n, "keys") in embree:
            keys["embree"] = embree[(n, "keys")]
        if n in vkr:
            keys["vkr"] = vkr[n]
        kv = {}
        if (n, "kv") in jaesung:
            kv["jaesung"] = jaesung[(n, "kv")]
        if (n, "kv") in embree:
            kv["embree"] = embree[(n, "kv")]
        writer.writerow({
            "n": n,
            "jaesung_keys_ms": keys.get("jaesung", ""),
            "embree_keys_ms": keys.get("embree", ""),
            "vkr_keys_p50_ms": keys.get("vkr", ""),
            "winner_keys": min(keys, key=keys.get) if keys else "",
            "jaesung_kv_ms": kv.get("jaesung", ""),
            "embree_kv_ms": kv.get("embree", ""),
            "winner_kv": min(kv, key=kv.get) if kv else "",
        })

lines = []
lines.append("# Radix Sort Manual Confirmation Summary\n")
lines.append(f"Output directory: `{out_dir}`\n")
lines.append("## Keys-only winners\n")
lines.append("| N | jaesung ms | Embree ms | VkRadixSort p50 ms | winner |\n")
lines.append("|---:|---:|---:|---:|---|\n")
for n in sizes:
    keys = {}
    if (n, "keys") in jaesung:
        keys["jaesung"] = jaesung[(n, "keys")]
    if (n, "keys") in embree:
        keys["embree"] = embree[(n, "keys")]
    if n in vkr:
        keys["vkr"] = vkr[n]
    winner = min(keys, key=keys.get) if keys else ""
    lines.append(f"| {n} | {keys.get('jaesung', '')} | {keys.get('embree', '')} | {keys.get('vkr', '')} | {winner} |\n")

lines.append("\n## Key-value winners\n")
lines.append("| N | jaesung ms | Embree ms | winner |\n")
lines.append("|---:|---:|---:|---|\n")
for n in sizes:
    kv = {}
    if (n, "kv") in jaesung:
        kv["jaesung"] = jaesung[(n, "kv")]
    if (n, "kv") in embree:
        kv["embree"] = embree[(n, "kv")]
    winner = min(kv, key=kv.get) if kv else ""
    lines.append(f"| {n} | {kv.get('jaesung', '')} | {kv.get('embree', '')} | {winner} |\n")

if vkr_dist:
    lines.append("\n## VkRadixSort distribution\n")
    lines.append("| N | min | p50 | max |\n")
    lines.append("|---:|---:|---:|---:|\n")
    for n, (mn, med, mx) in vkr_dist.items():
        lines.append(f"| {n} | {mn:.6f} | {med:.6f} | {mx:.6f} |\n")

summary_md.write_text("".join(lines))
print(f"Wrote {summary_csv}")
print(f"Wrote {summary_md}")
PY
}

run_vkradixsort_sweep() {
  require_file "$VKRS_HEADER"
  require_file "$VKRS_EXE"
  local out_csv="$OUT_DIR/vkradixsort_multi.csv"
  python3 - "$VKRS_DIR" "$VKRS_BUILD_DIR" "$VKRS_HEADER" "$VKRS_EXE" "$SIZES_CSV" "$VKRS_RUNS" "$out_csv" <<'PY'
import csv
import pathlib
import re
import statistics
import subprocess
import sys

root = pathlib.Path(sys.argv[1])
build = pathlib.Path(sys.argv[2])
header = pathlib.Path(sys.argv[3])
exe = pathlib.Path(sys.argv[4])
sizes = [int(x) for x in sys.argv[5].split(",") if x]
runs = int(sys.argv[6])
out_csv = pathlib.Path(sys.argv[7])
orig = header.read_text()
pattern = r"const uint32_t NUM_ELEMENTS = \d+;"
if not re.search(pattern, orig):
    raise SystemExit("NUM_ELEMENTS pattern not found")
rows = []
try:
    for n in sizes:
        print(f"\n[VkRadixSort] Configure NUM_ELEMENTS={n}")
        header.write_text(re.sub(pattern, f"const uint32_t NUM_ELEMENTS = {n};", orig))
        subprocess.run(["cmake", "--build", str(build), "--target", "multiradixsortexample", "-j"], check=True)
        sums, envs = [], []
        for run in range(1, runs + 1):
            p = subprocess.run([str(exe)], input="0\n", text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=True)
            m_sum = re.search(r"GPU_TIMESTAMP_RADIX_PASSES_SUM_MS\s+([0-9.]+)", p.stdout)
            m_env = re.search(r"GPU_TIMESTAMP_RADIX_PASSES_ENVELOPE_MS\s+([0-9.]+)", p.stdout)
            if not m_sum or not m_env or "Test passed." not in p.stdout:
                print(p.stdout)
                raise SystemExit(f"missing timestamp/correctness for n={n} run={run}")
            sum_ms = float(m_sum.group(1))
            env_ms = float(m_env.group(1))
            sums.append(sum_ms)
            envs.append(env_ms)
            rows.append({
                "backend": "vkradixsort-multi",
                "n": n,
                "sort": "keys",
                "run": run,
                "gpu_timestamp_sum_ms": sum_ms,
                "gpu_timestamp_envelope_ms": env_ms,
            })
            print(f"[VkRadixSort] n={n} run={run}/{runs} sum_ms={sum_ms:.6f} envelope_ms={env_ms:.6f}")
        print(f"[VkRadixSort] n={n} min={min(sums):.6f} p50={statistics.median(sums):.6f} max={max(sums):.6f}")
finally:
    header.write_text(orig)
    subprocess.run(["cmake", "--build", str(build), "--target", "multiradixsortexample", "-j"], check=False)

with out_csv.open("w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=["backend", "n", "sort", "run", "gpu_timestamp_sum_ms", "gpu_timestamp_envelope_ms"])
    writer.writeheader()
    writer.writerows(rows)
print(f"Wrote {out_csv}")
PY
}

mkdir -p "$OUT_DIR"

cat <<EOF
Radix Sort Manual Confirmation Runner

Root:       $ROOT_DIR
Output:     $OUT_DIR
Sizes:      $SIZES_CSV
Vk runs/N:  $VKRS_RUNS

You can override defaults, for example:
  SIZES_CSV=1048576,2097152 VKRS_RUNS=5 OUT_DIR=/tmp/radix_confirm ./run_radixsort_manual_confirm.sh
EOF

if confirm "Step 1: show current GPU load"; then
  show_gpu_load | tee "$OUT_DIR/gpu_load_before.txt"
fi

if confirm "Step 2: build shared vulkan_radix_sort bench"; then
  require_file "$VULKAN_BUILD_DIR/Makefile"
  cmake --build "$VULKAN_BUILD_DIR" --target bench -j"$(nproc)"
fi

if confirm "Step 3: run jaesung Vulkan sweep"; then
  require_file "$VULKAN_BUILD_DIR/bench"
  "$VULKAN_BUILD_DIR/bench" vulkan "$OUT_DIR/vulkan.csv" "$SIZES_CSV"
fi

if confirm "Step 4: run Embree CUDA port sweep"; then
  require_file "$VULKAN_BUILD_DIR/bench"
  "$VULKAN_BUILD_DIR/bench" embree-cuda "$OUT_DIR/embree_cuda.csv" "$SIZES_CSV"
fi

if confirm "Step 5: build VkRadixSort multi example"; then
  require_file "$VKRS_BUILD_DIR/Makefile"
  cmake --build "$VKRS_BUILD_DIR" --target multiradixsortexample -j"$(nproc)"
fi

if confirm "Step 6: run VkRadixSort multi timestamp sweep; this temporarily edits NUM_ELEMENTS and restores it"; then
  run_vkradixsort_sweep
fi

if confirm "Step 7: show final GPU load"; then
  show_gpu_load | tee "$OUT_DIR/gpu_load_after.txt"
fi

if confirm "Step 8: generate summary.csv and summary.md from available outputs"; then
  write_summary
fi

cat <<EOF

Done.
Output directory:
  $OUT_DIR

Recommended files to inspect:
  $OUT_DIR/vulkan.csv
  $OUT_DIR/embree_cuda.csv
  $OUT_DIR/vkradixsort_multi.csv
  $OUT_DIR/summary.csv
  $OUT_DIR/summary.md
EOF
