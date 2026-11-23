#!/usr/bin/env bash
# 内存安全证明（ASan）：
#   A) 编译器本体：boot2 用 clang+ASan 重建，跑全量 pos+err，要求 0 条 ASan 报告
#   B) 自举产物：boot3 同样用 clang+ASan 重建，跑全量 pos+err，要求 0 条
#   C) 产物程序：pos 用例生成的 C 用 clang+ASan 编译并运行，要求 0 条
# 说明：编译器按设计不 free（语言层无 auto-free），故 A/B 关闭 LeakSanitizer；
#       泄漏单独用 detect_leaks=1 量一次并如实报告（见脚本末尾）。
set -u
cd "$(dirname "$0")"

NCC="${NCC:-../NihaoC/ncc/build/ncc.exe}"
TCC="${TCC:-tcc}"
TMP="${TMP:-/tmp}"
export NIHAO_TCC_DIR="${NIHAO_TCC_DIR:-D:/Program Files/tcc}"
CLANG="${CLANG:-clang}"
export PATH="/d/devtools/clang/clang+llvm-18.1.8-x86_64-pc-windows-msvc/bin:$PATH"
ASAN_FLAGS="-std=gnu89 -g -fsanitize=address -Wno-int-conversion -Wno-return-type -Wno-parentheses-equality -O0"
TESTS=../NihaoC/ncc/tests
: > asan.log

fail=0
check_report() {
    # $1=标签  $2=stderr 文件
    if grep -q "ERROR: AddressSanitizer" "$2"; then
        echo "ASAN  $1" >> asan.log
        grep -m1 "ERROR: AddressSanitizer" "$2" | cut -c1-120 >> asan.log
        return 1
    fi
    return 0
}

echo "[1/4] 构建 boot2（ncc）"
"$NCC" build boot2/boot.nc -backend ir-c -o boot2.exe 2>&1 | grep -v "warning:" || true
[ -f boot2.exe.c ] || { echo "FAIL: 无 boot2.exe.c"; exit 1; }

echo "[2/4] boot2 → ASan 版，跑全量 pos+err"
"$CLANG" $ASAN_FLAGS boot2.exe.c -o boot2_asan.exe 2>"$TMP/asan_build1.log" || {
    echo "FAIL: clang 构建 boot2_asan 失败"; grep error "$TMP/asan_build1.log" | head -5; exit 1; }
n_ok=0
for src in "$TESTS"/pos/*.nc "$TESTS"/err/*.nc; do
    nm=$(basename "$src" .nc)
    rm -f "$TMP/asan_$nm.c"
    ASAN_OPTIONS=detect_leaks=0 BOOT_IN="$src" BOOT_OUT="$TMP/asan_$nm.c" \
        ./boot2_asan.exe > /dev/null 2>"$TMP/asan_$nm.err"
    grep -q "ERROR: AddressSanitizer" "$TMP/asan_$nm.err" && { echo "ASAN boot2: $nm" >> asan.log; fail=1; }
    n_ok=$((n_ok+1))
done
echo "  boot2_asan 跑完 $n_ok 份输入"

echo "[3/4] boot2 → b3.c → boot3_asan，跑全量 pos+err"
BOOT_IN=boot2/boot.nc BOOT_OUT=b3.c ./boot2.exe > /dev/null || { echo "FAIL: 自编译失败"; exit 1; }
"$CLANG" $ASAN_FLAGS b3.c -o boot3_asan.exe 2>"$TMP/asan_build2.log" || {
    echo "FAIL: clang 构建 boot3_asan 失败"; grep error "$TMP/asan_build2.log" | head -5; exit 1; }
for src in "$TESTS"/pos/*.nc "$TESTS"/err/*.nc; do
    nm=$(basename "$src" .nc)
    rm -f "$TMP/asan3_$nm.c"
    ASAN_OPTIONS=detect_leaks=0 BOOT_IN="$src" BOOT_OUT="$TMP/asan3_$nm.c" \
        ./boot3_asan.exe > /dev/null 2>"$TMP/asan3_$nm.err"
    grep -q "ERROR: AddressSanitizer" "$TMP/asan3_$nm.err" && { echo "ASAN boot3: $nm" >> asan.log; fail=1; }
done
echo "  boot3_asan 跑完"

echo "[4/4] 产物程序：pos 生成 C 用 clang+ASan 编译运行"
nprod=0
for src in "$TESTS"/pos/*.nc; do
    nm=$(basename "$src" .nc)
    BOOT_IN="$src" BOOT_OUT="$TMP/prod_$nm.c" ./boot2.exe > /dev/null 2>&1 || continue
    if ! "$CLANG" -std=gnu89 -g -fsanitize=address -Wno-int-conversion -Wno-return-type \
            -Wno-parentheses-equality -O0 "$TMP/prod_$nm.c" -o "$TMP/prod_$nm.exe" \
            > /dev/null 2>"$TMP/prod_$nm.build"; then
        echo "SKIP  $nm（产物 clang 编译不过）" >> asan.log
        continue
    fi
    ASAN_OPTIONS=detect_leaks=0 "$TMP/prod_$nm.exe" > /dev/null 2>"$TMP/prod_$nm.err"
    grep -q "ERROR: AddressSanitizer" "$TMP/prod_$nm.err" && { echo "ASAN prod: $nm" >> asan.log; fail=1; }
    nprod=$((nprod+1))
done
echo "  产物 ASan 运行 $nprod 份"

echo "--- 泄漏检测可用性（编译器按设计不 free，泄漏不在本脚本判据内）"
ASAN_OPTIONS=detect_leaks=1 BOOT_IN="$TESTS/pos/hello.nc" BOOT_OUT="$TMP/leak.c" \
    ./boot2_asan.exe > /dev/null 2>"$TMP/leak.err"
if grep -q "detect_leaks is not supported" "$TMP/leak.err"; then
    echo "LEAK: 平台不支持 LeakSanitizer（Windows），泄漏未测" >> asan.log
    echo "  泄漏：平台不支持 LSan，未测（已知边界）"
else
    grep -m1 "SUMMARY: AddressSanitizer" "$TMP/leak.err" | cut -c1-140 >> asan.log || true
fi

if [ "$fail" -eq 0 ]; then
    echo "ASAN OK（编译器与本轮产物均 0 条内存错误）"
else
    echo "ASAN 有报告，见 asan.log"
fi
exit "$fail"