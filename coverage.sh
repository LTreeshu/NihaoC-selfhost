#!/usr/bin/env bash
# 覆盖率度量：用 ncc 自己的 pos 用例喂 boot2，产物交 tcc，实跑输出与 .expect 比对。
# 判据与 ncc 门禁同源（stdout 逐字节，忽略 CRLF 差异），不另立标准。
set -u
cd "$(dirname "$0")"

BOOT="${BOOT:-./boot2.exe}"
NCC="${NCC:-../NihaoC/ncc/build/ncc.exe}"
NCC_TESTS="${NCC_TESTS:-../NihaoC/ncc/tests}"
TCC="${TCC:-tcc}"
TMP="${TMP:-/tmp}"

if [ ! -f "$BOOT" ] || [ "${REBUILD:-1}" = "1" ]; then
    echo "[build] boot2"
    "$NCC" build boot2/boot.nc -backend ir-c -o boot2.exe 2>&1 | grep -v "warning:" || true
    [ -f boot2.exe ] || { echo "boot2 构建失败"; exit 1; }
fi

pass=0
fail=0
skip=0
: > coverage.log

for src in "$NCC_TESTS"/pos/*.nc; do
    name=$(basename "$src" .nc)
    expect="$NCC_TESTS/pos/$name.expect"
    [ -f "$expect" ] || { skip=$((skip+1)); echo "SKIP  $name (no .expect)" >> coverage.log; continue; }

    if ! BOOT_IN="$src" BOOT_OUT="$TMP/cov_$name.c" timeout 5 "$BOOT" > "$TMP/cov_$name.gen" 2>&1; then
        fail=$((fail+1)); echo "FAIL  $name (boot2 崩溃/异常)" >> coverage.log; continue
    fi
    if ! timeout 10 "$TCC" "$TMP/cov_$name.c" -o "$TMP/cov_$name.exe" > "$TMP/cov_$name.tcc" 2>&1; then
        fail=$((fail+1))
        echo "FAIL  $name (tcc 编译失败): $(head -2 "$TMP/cov_$name.tcc" | tr '\n' ' ')" >> coverage.log
        continue
    fi
    timeout 5 "$TMP/cov_$name.exe" > "$TMP/cov_$name.out" 2>&1
    if diff -q --strip-trailing-cr "$TMP/cov_$name.out" "$expect" > /dev/null 2>&1; then
        pass=$((pass+1)); echo "OK    $name" >> coverage.log
    else
        fail=$((fail+1))
        echo "DIFF  $name" >> coverage.log
    fi
done

total=$((pass+fail+skip))
echo "pos 用例 $total 份：OK $pass / FAIL $fail / SKIP $skip"
echo "明细见 coverage.log"