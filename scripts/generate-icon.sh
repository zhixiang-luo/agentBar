#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PNG_1024="$ROOT_DIR/assets/logo.png"
ICNS_PATH="$ROOT_DIR/assets/AppIcon.icns"
RENDER_BIN="/tmp/agentbar-render-icon"

export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-/tmp/agentbar-clang-cache}"

if [[ ! -f "$PNG_1024" ]] || [[ "$ROOT_DIR/scripts/render-icon.swift" -nt "$PNG_1024" ]]; then
  swiftc "$ROOT_DIR/scripts/render-icon.swift" -o "$RENDER_BIN"
  "$RENDER_BIN" "$PNG_1024"
  rm -f "$RENDER_BIN"
fi

# 使用 sips 生成各尺寸 PNG 并按 Apple ICNS 二进制规范封装为 AppIcon.icns
/usr/bin/python3 - "$PNG_1024" "$ICNS_PATH" <<'PY'
import os, struct, subprocess, sys, tempfile

src_png, out_icns = sys.argv[1], sys.argv[2]
# 标准 macOS ICNS PNG-based OSTypes
specs = [
    (b"icp4", 16),
    (b"icp5", 32),
    (b"icp6", 64),
    (b"ic07", 128),
    (b"ic08", 256),
    (b"ic09", 512),
    (b"ic10", 1024),
    (b"ic11", 32),
    (b"ic12", 64),
    (b"ic13", 256),
    (b"ic14", 512),
]

chunks = bytearray()
with tempfile.TemporaryDirectory(prefix="agentbar-icns-") as tmp:
    resized_cache = {}
    for ostype, px in specs:
        if px not in resized_cache:
            if px == 1024:
                with open(src_png, "rb") as f:
                    resized_cache[px] = f.read()
            else:
                out_p = os.path.join(tmp, f"icon_{px}.png")
                subprocess.run(
                    ["sips", "-s", "format", "png", "-z", str(px), str(px), src_png, "--out", out_p],
                    check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
                )
                with open(out_p, "rb") as f:
                    resized_cache[px] = f.read()
        data = resized_cache[px]
        chunks.extend(ostype)
        chunks.extend(struct.pack(">I", len(data) + 8))
        chunks.extend(data)

total_len = len(chunks) + 8
with open(out_icns, "wb") as f:
    f.write(b"icns")
    f.write(struct.pack(">I", total_len))
    f.write(chunks)

print(f"Generated ICNS ({total_len} bytes): {out_icns}")
PY
