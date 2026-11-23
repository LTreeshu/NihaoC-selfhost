#!/usr/bin/env bash
# 自编译闭环（S3）：
#   1) ncc 构建 boot2
#   2) boot2 编译自身源码 → b3.c → tcc → boot3
#   3) boot3 再编译自身源码 → b4.c，要求 b3.c 与 b4.c 逐字节相同（不动点）
#   4) boot3 / boot4 跑样例，输出与期望一致
set -u
cd "$(dirname "$0")"

NCC="${NCC:-../NihaoC/ncc/build/ncc.exe}"
TCC="${TCC:-tcc}"
TMP="${TMP:-/tmp}"
export NIHAO_TCC_DIR="${NIHAO_TCC_DIR:-D:/Program Files/tcc}"

fail=0

echo "[1/4] ncc 构建 boot2"
"$NCC" build boot2/boot.nc -backend ir-c -o boot2.exe 2>&1 | grep -v "warning:" || true
[ -f boot2.exe ] || { echo "FAIL: boot2 构建失败"; exit 1; }

echo "[2/4] boot2 编译自身 → boot3"
rm -f boot3.exe
BOOT_IN=boot2/boot.nc BOOT_OUT=b3.c ./boot2.exe > /dev/null || { echo "FAIL: boot2 自编译失败"; exit 1; }
if ! "$TCC" b3.c -o boot3.exe 2>"$TMP/tcc1.log"; then
    echo "FAIL: tcc 构建 boot3 失败"; grep -v "warning:" "$TMP/tcc1.log" | head -5; exit 1
fi

echo "[3/4] boot3 自编译 → 不动点比对"
BOOT_IN=boot2/boot.nc BOOT_OUT=b4.c ./boot3.exe > /dev/null || { echo "FAIL: boot3 自编译失败"; exit 1; }
if cmp -s b3.c b4.c; then
    echo "FIXPOINT OK（b3.c 与 b4.c 逐字节相同）"
else
    echo "FIXPOINT FAIL（b3.c 与 b4.c 不同）"
    diff b3.c b4.c | head -10
    fail=1
fi
rm -f boot4.exe
if ! "$TCC" b4.c -o boot4.exe 2>"$TMP/tcc2.log"; then
    echo "FAIL: tcc 构建 boot4 失败"; grep -v "warning:" "$TMP/tcc2.log" | head -5; fail=1
fi

echo "[4/4] boot3 / boot4 跑样例"
for b in boot3 boot4; do
    for src in samples/*.n0; do
        name=$(basename "$src" .n0)
        BOOT_IN="$src" BOOT_OUT="sh_$name.c" "./$b.exe" > /dev/null || { echo "FAIL $b $name（自举产物编译失败）"; fail=1; continue; }
        "$TCC" "sh_$name.c" -o "sh_$name.exe" > /dev/null 2>&1 || { echo "FAIL $b $name（tcc 失败）"; fail=1; continue; }
        "./sh_$name.exe" > "sh_$name.out" 2>&1
        if diff -q --strip-trailing-cr "sh_$name.out" "samples/$name.expected" > /dev/null; then
            echo "PASS $b $name"
        else
            echo "FAIL $b $name（输出不符）"
            fail=1
        fi
    done
done

if [ "$fail" -eq 0 ]; then
    echo "SELFHOST OK"
else
    echo "SELFHOST 有失败"
fi
exit "$fail"