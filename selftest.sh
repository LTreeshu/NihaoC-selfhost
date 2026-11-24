#!/usr/bin/env bash
# 自举回归：用指定编译器（缺省 boot2.exe）编译 tests/*.nc → tcc → 实跑 → 与 .expect 比对
# 用法: ./selftest.sh [编译器]      例：./selftest.sh boot3.exe
set -u
cd "$(dirname "$0")"

CC_BIN="${1:-./boot2.exe}"
TCC="${TCC:-D:/Program Files/tcc/tcc}"
[ -x "$CC_BIN" ] || { echo "缺少编译器：$CC_BIN"; exit 1; }

mkdir -p selftest_out 2>/dev/null || true
ok=0
bad=0
skipped=0

for src in tests/*.nc; do
    n=$(basename "$src" .nc)
    exp="tests/$n.expect"
    out="selftest_out/$n.c"
    exe="selftest_out/$n.exe"
    rm -f "$out" "$exe"
    if ! BOOT_IN="$src" BOOT_OUT="$out" "$CC_BIN" > "selftest_out/$n.log" 2>&1; then
        echo "FAIL $n: 编译失败"; bad=$((bad+1)); continue
    fi
    if ! "$TCC" -o "$exe" "$out" > "selftest_out/$n.tcc.log" 2>&1; then
        echo "FAIL $n: 产物 C 不可编译"; bad=$((bad+1)); continue
    fi
    "$exe" > "selftest_out/$n.out" 2>&1
    if diff -q --strip-trailing-cr "selftest_out/$n.out" "$exp" > /dev/null; then
        ok=$((ok+1))
    else
        echo "FAIL $n: 输出不符"
        echo "  期望: $(head -1 "$exp")"
        echo "  实际: $(head -1 "selftest_out/$n.out")"
        bad=$((bad+1))
    fi
done

echo "自举回归（$(basename "$CC_BIN")）：OK $ok / FAIL $bad / SKIP $skipped"
[ "$bad" -eq 0 ] && echo "SELFTEST OK"
exit "$bad"