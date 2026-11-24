#!/usr/bin/env bash
# 交叉后端验证：
#   1) 用 zig 把 boot2 的 C 交叉编译成 riscv64 / loongarch64 静态可执行
#   2) 三个编译器（native / rv64 / la64）各自跑全部 pos+err 输入
#   3) 逐份比对生成的 C 是否逐字节相同（err 用例比对 rc + 是否产出）
#   4) 抽 4 份产物：用 zig 交叉编译成目标架构，qemu 执行，输出与 .expect 比对
set -u
cd "$(dirname "$0")"
# 阻止 Git Bash 把 /mnt/... 参数转成 Windows 路径
export MSYS2_ARG_CONV_EXCL='*'
export MSYS_NO_PATHCONV=1

NCC="${NCC:-../NihaoC/ncc/build/ncc.exe}"
TCC="${TCC:-tcc}"
export NIHAO_TCC_DIR="${NIHAO_TCC_DIR:-D:/Program Files/tcc}"
TESTS=../NihaoC/ncc/tests
BASE=/mnt/e/qoder-workspace/qwenwork/NihaoC-selfhost
CC_FLAGS="-std=gnu89 -Wno-int-conversion -Wno-return-type -Wno-parentheses-equality"

fail=0
mkdir -p x 2>/dev/null || true

echo "[1/4] ncc 构建 boot2 + zig 交叉编译"
"$NCC" build boot2/boot.nc -backend ir-c -o boot2.exe 2>&1 | grep -v "warning:" || true
[ -f boot2.exe.c ] || { echo "FAIL: 无 boot2.exe.c"; exit 1; }
for t in rv64:riscv64 la64:loongarch64; do
    tag=${t%%:*}
    arch=${t##*:}
    zig cc -target "$arch-linux-musl" -static $CC_FLAGS -O1 boot2.exe.c -o "boot2_$tag" 2>"x/build_$tag.log" || {
        echo "FAIL: zig 构建 boot2_$tag 失败"; grep -i error "x/build_$tag.log" | head -5; exit 1; }
done
echo "  boot2_rv64 / boot2_la64 就绪"

echo "[2/4] native 跑全部输入"
for f in "$TESTS"/pos/*.nc "$TESTS"/err/*.nc; do
    n=$(basename "$f" .nc)
    rm -f "x/nat__$n.c"
    BOOT_IN="$f" BOOT_OUT="x/nat__$n.c" BOOT_INC="$TESTS/pos" ./boot2.exe \
        > "x/nat__$n.stdout" 2> "x/nat__$n.stderr"
    echo $? > "x/nat__$n.rc"
done
echo "  完成"

echo "[3/4] qemu 里跑交叉编译器（rv64 / la64）"
for t in rv64:qemu-riscv64-static la64:qemu-loongarch64-static; do
    tag=${t%%:*}
    qemu=${t##*:}
    wsl.exe -- bash -lc "bash /mnt/e/qoder-workspace/qwenwork/NihaoC-selfhost/xrun.sh '$qemu' '$BASE/boot2_$tag' '$tag'" 2>&1 | tr -d '\0' | tail -1
done

echo "[4/4] 逐份比对 + 抽样执行"
pos_ok=0; pos_bad=0; err_ok=0; err_bad=0
for f in "$TESTS"/pos/*.nc; do
    n=$(basename "$f" .nc)
    for tag in rv64 la64; do
        if cmp -s "x/nat__$n.c" "x/${tag}__$n.c"; then pos_ok=$((pos_ok+1)); else
            pos_bad=$((pos_bad+1)); echo "DIFF pos/$n ($tag)" >> cross.log; fail=1
        fi
    done
done
for f in "$TESTS"/err/*.nc; do
    n=$(basename "$f" .nc)
    for tag in rv64 la64; do
        rn=$(cat "x/nat__$n.rc"); rt=$(cat "x/${tag}__$n.rc")
        fn=0; [ -f "x/nat__$n.c" ] && fn=1
        ft=0; [ -f "x/${tag}__$n.c" ] && ft=1
        if [ "$rn" = "$rt" ] && [ "$fn" = "$ft" ]; then err_ok=$((err_ok+1)); else
            err_bad=$((err_bad+1)); echo "DIFF err/$n ($tag) rc $rn/$rt file $fn/$ft" >> cross.log; fail=1
        fi
    done
done
echo "  产物比对：pos $pos_ok 相同 / $pos_bad 不同；err $err_ok 一致 / $err_bad 不一致"

echo "--- 抽样执行（生成 C 交叉编译后 qemu 跑，比对 .expect）"
for n in hello fib ir_struct is_pattern_forms type_forms; do
    src="$TESTS/pos/$n.nc"
    [ -f "$src" ] || src="samples/$n.n0"
    [ -f "$src" ] || continue
    BOOT_IN="$src" BOOT_OUT="x/exec_$n.c" ./boot2.exe > /dev/null 2>&1 || continue
    exp="$TESTS/pos/$n.expect"
    [ -f "$exp" ] || exp="samples/$n.expected"
    for t in rv64:riscv64:qemu-riscv64-static la64:loongarch64:qemu-loongarch64-static; do
        tag=${t%%:*}; rest=${t#*:}; arch=${rest%%:*}; qemu=${rest##*:}
        zig cc -target "$arch-linux-musl" -static $CC_FLAGS -O1 "x/exec_$n.c" -o "x/exec_${n}_$tag" 2>/dev/null || continue
        wsl.exe -- bash -lc "cd $BASE && $qemu ./x/exec_${n}_$tag" 2>&1 | tr -d '\0' > "x/exec_${n}_$tag.out"
        if diff -q --strip-trailing-cr "x/exec_${n}_$tag.out" "$exp" > /dev/null; then
            echo "  PASS $n ($tag)"
        else
            echo "  FAIL $n ($tag)"; fail=1
        fi
    done
done

if [ "$fail" -eq 0 ]; then
    echo "CROSS OK"
else
    echo "CROSS 有失败，见 cross.log"
fi
exit "$fail"