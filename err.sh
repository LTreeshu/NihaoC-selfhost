#!/usr/bin/env bash
# err 语料度量：boot 必须「报错 + 不出产物 + stderr 命中 .expect 连续子串」（与 ncc 门禁同判据）
set -u
cd "$(dirname "$0")"

BOOT="${BOOT:-./boot2.exe}"
NCC_TESTS="${NCC_TESTS:-../NihaoC/ncc/tests}"
TMP="${TMP:-/tmp}"
: > err.log

pass=0
fail=0

for src in "$NCC_TESTS"/err/*.nc; do
    name=$(basename "$src" .nc)
    expect="$NCC_TESTS/err/$name.expect"
    [ -f "$expect" ] || { echo "SKIP  $name (no .expect)" >> err.log; continue; }
    rm -f "$TMP/err_$name.c"

    out=$(BOOT_IN="$src" BOOT_OUT="$TMP/err_$name.c" "$BOOT" 2>&1)
    rc=$?

    want=$(cat "$expect")
    reason=""
    if [ "$rc" -eq 0 ]; then
        reason="rc=0（没报错）"
    elif [ -f "$TMP/err_$name.c" ]; then
        reason="仍产出文件"
    elif ! printf '%s' "$out" | grep -qF "$want"; then
        reason="消息不含期望串"
    fi

    if [ -z "$reason" ]; then
        pass=$((pass+1))
        echo "OK    $name" >> err.log
    else
        fail=$((fail+1))
        echo "FAIL  $name [$reason]" >> err.log
    fi
done

echo "err 用例：OK $pass / FAIL $fail"
echo "明细见 err.log"