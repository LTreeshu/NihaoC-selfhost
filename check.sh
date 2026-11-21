#!/usr/bin/env bash
# 一键：编 boot1 → 逐个样例生成 C → tcc 编译 → 运行 → 比对期望
set -u
cd "$(dirname "$0")"

NCC="${NCC:-../NihaoC/ncc/build/ncc.exe}"
TCC="${TCC:-tcc}"
export NIHAO_TCC_DIR="${NIHAO_TCC_DIR:-D:/Program Files/tcc}"

fail=0

echo "[1/2] 编译 boot1"
"$NCC" build boot1/boot.nc -backend ir-c -o boot1.exe 2>&1 | grep -v "warning:" || true
if [ ! -f boot1.exe ]; then
    echo "FAIL: boot1 构建失败"
    exit 1
fi

echo "[2/2] 样例"
for src in samples/*.n0; do
    name=$(basename "$src" .n0)
    cp "$src" input.n0
    if ! ./boot1.exe > /dev/null; then
        echo "FAIL $name (boot1 运行失败)"
        fail=1
        continue
    fi
    if ! "$TCC" output.c -o prog.exe > /dev/null 2>&1; then
        echo "FAIL $name (tcc 编译失败)"
        fail=1
        continue
    fi
    ./prog.exe > "$name.actual" 2>&1
    if diff -q --strip-trailing-cr "$name.actual" "samples/$name.expected" > /dev/null; then
        echo "PASS $name"
    else
        echo "FAIL $name"
        diff --strip-trailing-cr "samples/$name.expected" "$name.actual" | head -6
        fail=1
    fi
done

if [ "$fail" -eq 0 ]; then
    echo "ALL SAMPLES OK"
else
    echo "有样例失败"
fi
exit "$fail"
