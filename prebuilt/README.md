# 预编译版本：NihaoC 自举编译器 `nihao-selfhost.exe`

这是**自举产物**——由 NihaoC 编译器链条自己编出来的编译器（非 ncc 直接构建）。

## 来源与可信度

- 生成链：`ncc v0.2.3 (ir-c)` → `boot2` → `boot2` 编译 `boot.nc` → `boot3` → `boot3` 编译 `boot.nc` → **`boot4`**（本二进制）。
- 源码：`boot2/boot.nc`，对应提交 `927986c`。
- 不动点已验证：`boot3` 与 `boot4` 编译同一份 `boot.nc` 得到的 C **逐字节相同**（`b3.c ≡ b4.c`）。
- 平台：Windows x86-64，用 tcc 0.9.27 链接。
- 验收（均以本二进制运行）：pos 73/73、err 36/36、selftest 6/6、samples 全绿。

## 用法

本编译器把 NihaoC 源码翻成 C。它通过环境变量取输入/输出路径（缺省 `input.n0` / `output.c`）：

```bash
# 1) NihaoC → C
BOOT_IN=path/to/prog.nc BOOT_OUT=prog.exe.c ./nihao-selfhost.exe
# 2) C → 可执行
tcc prog.exe.c -o prog.exe
# 3) 运行
./prog.exe
```

> 诊断写 stdout；出错时 rc≠0 且不产出文件。

## 完整性

```bash
sha256sum -c SHA256SUMS.txt
```

## 复现

在本仓库根目录（需先按 README「怎么跑」把 ncc 重建为 v0.2.3）：

```bash
./selfhost.sh          # 产出 boot2/boot3/boot4 并校验不动点
cp boot4.exe prebuilt/nihao-selfhost.exe
```
