#!/usr/bin/env bash
# 在 WSL 里跑：用 qemu-user 执行交叉编译出的 boot 编译器，遍历全部 pos/err 输入
# 用法: xrun.sh <qemu 可执行> <boot 二进制> <标签>
set -u
BASE=/mnt/e/qoder-workspace/qwenwork/NihaoC-selfhost
SRC=$BASE/../NihaoC/ncc/tests
Q="$1"
BIN="$2"
TAG="$3"
OUT=$BASE/x
# /mnt/e 上的文件没有执行位，先拷到 /tmp 再加权限
cp "$BIN" "/tmp/boot2_$TAG" && chmod +x "/tmp/boot2_$TAG" || { echo "copy fail"; exit 1; }
BIN="/tmp/boot2_$TAG"

for f in "$SRC"/pos/*.nc "$SRC"/err/*.nc; do
    n=$(basename "$f" .nc)
    rm -f "$OUT/${TAG}__$n.c"
    BOOT_IN="$f" BOOT_OUT="$OUT/${TAG}__$n.c" BOOT_INC="$SRC/pos" \
        "$Q" "$BIN" > "$OUT/${TAG}__$n.stdout" 2> "$OUT/${TAG}__$n.stderr"
    echo $? > "$OUT/${TAG}__$n.rc"
done
echo "cross $TAG done: $(ls -1 "$OUT"/${TAG}__*.rc | wc -l) 份"