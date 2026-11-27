# NihaoC 自举编译器（自举工作区）

用 NihaoC 自己写 NihaoC 编译器。本目录**独立于** NihaoC 仓库：编译器侧的改动走仓库内的
本地分支 `selfhost`（不推送、不并入 `PB`），自举编译器本体在这里演进。

- 目标平台：`-backend ir-c`（唯一带宿主 libc 与文件系统的可信链路）
- 编译器侧准备记录：`NihaoC/docs/SELFHOST.md`（分支 `selfhost`）
- 当前阶段：**S1 / S2 / S3 全部达成** —— `boot2` 吃下 ncc 自带 **全部 pos 用例**
  （73/73，0 FAIL）与 **全部 err 诊断用例**（36/36），并且**自编译闭环打通**：
  `boot2` 编译自身得到 `boot3`，`boot3` 再编译自身得到的 `b4.c` 与 `b3.c` **逐字节相同**。

## 目录

```
NihaoC-selfhost/
├── README.md          本文件
├── check.sh           S1 回归：编 boot1 → 跑样例 → tcc → 比对期望
├── coverage.sh        S2 度量：用 ncc 自带 pos 用例喂 boot2，逐份比对 .expect
├── err.sh             诊断度量：err 用例必须「报错 + 无产物 + 消息命中 .expect」
├── selfhost.sh        S3 闭环：ncc→boot2→boot3→不动点 + 样例 + boot3/boot4 全语料
├── asan.sh            内存安全：boot2/boot3/boot4 与产物程序全部过 ASan
├── cross.sh           交叉后端：zig 交叉编译 + WSL qemu 执行与产物比对
├── xrun.sh            （cross.sh 在 WSL 侧调用的遍历脚本）
├── coverage.log       最近一次 pos 度量明细（boot2）
├── err.log            最近一次 err 度量明细（boot2）
├── coverage-boot3.log boot3（第一代自举产物）的 pos 明细
├── err-boot3.log      boot3 的 err 明细
├── coverage-boot4.log boot4（第二代自举产物）的 pos 明细
├── err-boot4.log      boot4 的 err 明细
├── boot1/boot.nc      Stage 1：N0 子集 → C（约 380 行）
├── boot2/boot.nc      Stage 2：NihaoC 语法 → C（token 化 + 直接出码，约 1900 行）
├── samples/*.n0       N0 样例 + *.expected
└── probes/*.nc        能力探针（每条对应一处实测边界）
```

## 怎么跑

> **前置：ncc 必须是 0.2.x。** 本工作区依赖 NihaoC 仓库编译出的 `ncc`（`ir-c` 后端）。
> 若 `NihaoC/ncc/build/ncc.exe` 是较旧/较新分支的陈旧产物（实测 v0.5.0 会让 `boot1` 报
> `undeclared variable`、`boot2` 报 `expected '}' got TOK_EOF`），先进 `NihaoC/ncc` 用 xmake
> 重新构建（当前源码版本 v0.2.3），再回来跑本目录脚本：
>
> ```bash
> cd ../NihaoC/ncc && xmake -r -y        # 产出 build/ncc.exe（v0.2.3）
> ```

```bash
export NIHAO_TCC_DIR="D:/devtools/tcc"    # tcc 实际所在目录（按机器调整）
export TCC="$NIHAO_TCC_DIR/tcc"           # 脚本里 tcc 的默认路径可能指向别处，显式覆盖
export NCC=../NihaoC/ncc/build/ncc.exe    # 可覆盖

./check.sh        # S1：两个样例全绿
./coverage.sh     # S2：打印 "pos 用例 75 份：OK x / FAIL y / SKIP z"
```

## 覆盖率（S2 的验收尺子）

判据与 ncc 门禁同源：**boot2 生成 C → tcc 编译 → 实跑 → 与 `tests/pos/*.expect` 逐字节比对**
（忽略 CRLF），不另立标准。

| 轮次 | OK / 75 | 关键修复 |
|---|---|---|
| 起点 | 8 | — |
| 1 | 31 | `==`/`<`/`>` 被当单字符吞掉；下标/切片重写；聚合零初始化 `{0}` |
| 2 | 36 | bare `return` 不再吞右花括号；词法指数/二进制字面量；`do` 按前测循环；`switch` 补 `break` |
| 3 | 44 | 返回类型带 `flow/const/static` 的 `void` → `void*`；`len()` 多维；`sizeof(T[N])` |
| 4 | 47 | `var {a=1,b=2} T` 多变量声明；`is _` 通配；`for (i32)` 括号类型 |
| 5 | 55 | **切片**：`p.(T[N])` 数组指针、`p[]` 空下标解引用、切片左值 `a[lo..hi] = {…}` / `= "str"`、切片读入声明数组（memcpy）、`len(slice)`；**成员默认值**：结构体/联合/聚合数组（含多维、指定式混写） |
| 6 | **73** | 多变量声明（含数组/字符串）、`fx32/fx64`、`is` 改为 `if/else-if` 首匹配即止（含 `+5`/`-3`/`-9..-5`）、前缀 `++/--`、指针表达式隐式声明、聚合指针 `->` 转 `((T*)p)->m`、`sizeof(聚合)=成员数×8` 与真实 `alignof`、`structof/holdof/unionof/bitoffsetof`、顶层非常量初值挪进 `__nihao_init()`、**cooking 编译期常量与宏式编译期函数**、`use` 模块内联 |

当前：**73 OK / 0 FAIL / 2 SKIP**（2 份为无 `.expect` 的模块型用例，只比产物不改输出）。
即 **ncc 0.2.x 的 pos 语料已全覆盖**。

### err 诊断（`./err.sh`）

判据与 ncc 门禁同源：**rc != 0 + 不产出文件 + 消息命中 `.expect` 连续子串**。

```
err 用例：OK 36 / FAIL 0
```

覆盖的诊断族：`?=`/`?.` 已移除、`linkas` 未实现、`[[未知属性]]`、cooking 非法项、
`is` 畸形/悬空/空区间/循环外、`const` 重绑定与自有存储写入、泛型 `void` 指针的
下标/成员访问、`.(void)`、越界读（`malloc` 尺寸 vs 显式读宽）、`len` 长度不可知、
字符串/定长数组容量（单变量、多变量、切片三路）、聚合默认值展开上限，以及
可见性与所有权（`flow/static/const` 转移矩阵、借用冻结、所有权转移后失效、冻结源再转移）。

> 口径说明：ncc 把诊断写 stderr，本编译器目前写 **stdout**（harness 合并两股流比对）；
> 诊断规则是按语料逐族实现的，**不是** ncc 那份完整实现的等价物（详见下方「已知边界」）。

### 自编译闭环（`./selfhost.sh`）

```
[1/6] ncc 构建 boot2
[2/6] boot2 编译自身 → b3.c → boot3
[3/6] boot3 编译自身 → b4.c，FIXPOINT OK（b3.c 与 b4.c 逐字节相同）
[4/6] boot3 / boot4 跑 samples/*.n0 → 全部 PASS
[5/6] boot3 跑全量 pos / err 语料 → boot3: pos OK 73 / err OK 36
[6/6] boot4 跑全量 pos / err 语料 → boot4: pos OK 73 / err OK 36
SELFHOST OK
```

第 5、6 步是**两代自举产物的等价性验收**：

| 编译器 | 来源 | pos | err |
|---|---|---|---|
| `boot2` | ncc 编译 | 73/73 | 36/36 |
| `boot3` | boot2 编译 | 73/73 | 36/36 |
| `boot4` | boot3 编译 | 73/73 | 36/36 |

明细分别在 `coverage.log`/`err.log`、`coverage-boot3.log`/`err-boot3.log`、`coverage-boot4.log`/`err-boot4.log`。

### 交叉后端（`./cross.sh`，riscv64 / loongarch64）

前置：`zig`（Windows 侧）、WSL 里 `apt install -y qemu-user-static`（提供 `qemu-riscv64-static` / `qemu-loongarch64-static`）。

做法：用 **zig 0.15.2** 把 `boot2.exe.c` 交叉编译成 `riscv64-linux-musl` / `loongarch64-linux-musl`
静态可执行，在 **WSL + qemu-user-static 8.2.2** 下执行，与 native 版逐份对比。

| 检查 | 规模 | 结果 |
|---|---|---|
| 生成的 C 与 native 逐字节相同 | 75 份输入 × 2 目标 = **150** | **150 相同 / 0 不同** |
| err 用例行为一致（rc + 是否产出） | 36 × 2 = **72** | **72 一致 / 0 不一致** |
| 产物程序在目标架构执行（`hello`/`fib`/`ir_struct`/`is_pattern_forms`/`type_forms` × 2 目标） | 10 次 | **10 PASS**（输出与 `.expect` 一致） |

为此顺带修了一处**跨平台缺陷**：`fopen(..., "w")` 在 Windows 是文本模式，会把 `\n` 写成 `\r\n`，
导致跨平台产物无法逐字节比对；已改成 `"rb"` / `"wb"` 二进制模式。

**边界**：这里验证的是「**boot 编译器自身可移植、且在不同架构上产出完全相同的 C**」，
不是 ncc 的 `ir-riscv64` / `ir-loongarch64` 汇编后端（那两档只出 `.s`，属 ncc 侧能力，boot 尚未接入）。

### 自举回归（`./selftest.sh [编译器]`）

`tests/` 下放「自举编译器自身要保证的能力」用例，走 `编译 → tcc → 实跑 → 与 .expect 逐字节比对`：

```
$ ./selftest.sh            # 用 boot2
$ ./selftest.sh ./boot3.exe  # 用自举产物
自举回归（boot2.exe）：OK 7 / FAIL 0 / SKIP 0
```

当前 7 份：`array_param`（数组形参）、`struct_value_return`（按值返回结构体）、
`struct_array_param`（结构体数组形参 + 成员改写），`free_heap`（堆分配 + `free`）、
`agg_array_member`（聚合数组成员经 `.(T)` 读写）、`brace_newline`（函数体 `{` 换行到下一行），
以及本轮新增的 `u64_type`（`u64` 类型：声明/算术/`sizeof`/数组/`len`，此前 `code_of` 缺该类型直接崩）。
前几份把此前 README 标注为 ❌/⚠️ 或未实现的语法固化为回归：在 ncc v0.2.3 下，boot2 / boot3 / boot4
三个编译器均 `OK 7 / FAIL 0`。其中 `array_param` 等曾暴露真实缺陷——
`emit_protos()` 生成原型时丢掉数组后缀，定义处是 `int32_t a[]`、原型是 `int32_t`，
tcc 报 `incompatible types for redefinition`，且**编译器本身不报错**（静默产出不可编译的 C）。
修法是原型侧把 `pd > 0` 的类型衰减成 `T*`。

### 内存安全（`./asan.sh`）

tcc 不支持 ASan，故用 clang 18 + `-fsanitize=address` 重建 `boot2.exe.c` / `b3.c` / `b4.c`：

| 对象 | 规模 | 结果 |
|---|---|---|
| `boot2_asan`（编译器本体） | 跑 pos+err 共 111 份输入 | **0 条 ASan 报告** |
| `boot3_asan`（第一代自举产物） | 跑 pos+err 共 111 份输入 | **0 条 ASan 报告** |
| `boot4_asan`（第二代自举产物） | 跑 pos+err 共 111 份输入 | **0 条 ASan 报告** |
| 产物程序（pos 生成 C 用 ASan 重编） | 72 份可执行 | **0 条 ASan 报告** |

3 份 SKIP 是模块型/无 `main` 用例（`mathmod` / `module_top_forms` / `use_mod`），clang 链接期无入口，与内存安全无关。

**泄漏**：本平台 clang 的 LeakSanitizer **不支持 Windows**（实测 `detect_leaks is not supported on this platform`），
故泄漏未测；且编译器按设计不 `free`（NihaoC 语言层没有 auto-free），泄漏是已知边界，不在“内存安全”判据内。

这轮 ASan 与自编译各揪出一个真 bug：

1. **字符串字面量被直接写入**（`ir_str` 产物在 `.rdata` 上写 → ASan 报错）：已按 ncc PB-89 语义改成
   声明处 `__nihao_strdup()` 可写副本（`const` 仍绑只读池）。
2. **自编译源码被截断**：`boot2` 自身源码涨到 136 KB，超过它读入缓冲的 128 KB，导致 `b3.c` 里 `main`
   尾部（输出写盘、诊断收尾）整段丢失；已把源缓冲提到 512 KB、token 数组提到 1M 个 i32，并给
   `put_tok` 加溢出保护。
3. 附带修掉 `if (cond)` 的右括号未消费（曾让产物里出现 `0;` 与 `else;`，自编译时才暴露）。

## N0 / boot1（S1，已完成）

N0 是 NihaoC 的极小子集（`func` / 声明 / 赋值 / `if-else` / `while` / `return` / `puts` / `print`），
`boot1` 把 N0 翻成 C。样例 `hello.n0` / `fib.n0` 全部 PASS。

## boot2 覆盖的语法（S2，进行中）

- 词法：标识符/关键字、十进制/十六进制/二进制/浮点（含指数）、字符串（含转义）、字符、
  多字符运算符（`-> == != <= >= && || ++ -- << >> += … .. ... =>`）、`//` 与 `/* */` 注释
- 顶层：`module` / `use` / `link`（跳过）、`alias`、`struct` / `union` / `enum`（含位域）、
  全局 `const/var/static/flow` 标量、函数定义（参数前缀、返回类型前缀、`[[attr]]`）、`cooking` 跳过
- 声明：`name T [dims] [= init]`、多变量 `var {a=1,b=2} T`、维度规范化
  （`[]`→`[8]`、`[N..]`/`[..N]`/`[N...]` → `[N]`）、聚合/数组零初始化 `{0}`、指定式 `.m = v`
- 表达式：完整优先级、赋值与复合赋值、`++/--`、三元、函数调用、下标、切片 `a[lo..hi]`、
  成员 `.`、指针成员 `->`、`.()` / `.(T)` / `.(T[N])`（按符号表推断指向类型）、`p[]` 空下标解引用、`&`
- 切片：读（`x = a[lo..hi]` → 指针；`T buf[N] = a[lo..hi]` → memcpy）、写
  （`a[lo..hi] = {…}` / `= "str"`，逐元素落位）、`len(slice)` 按 `hi-lo` 常量折叠
- 聚合默认值：结构体/联合成员默认值在声明处展开为 C 指定初始化器；聚合数组按元素逐项展开
  （含 `[...]` 默认容量 8、多维按维度嵌套花括号、扁平初值不追加尾数元素）
- 隐式声明：`p = &x`（指向 x 的指针）、`sl = a[lo..hi]`（元素指针 + 记录切片长度）、
  `talk = obj.member`（取成员类型）、`r = f(...)`（`int64_t`）
- 语句：`if / else if / else`、`while`（改写成可承载 `is` 的模式）、`do`（前测）、`for`
  （含 `for i = 0` 隐式声明）、`switch/case/default`（自动补 `break`）、`break/continue`、
  `goto`/标签、`return`（含 `return {a,b}` 复合返回）、`is` 模式（值/闭区间/`_`/可见性枚举/标识符）
- 内建：`print`→`printf`（字面量直通，否则 `%lld`）、`puts`、`len`、`sizeof`/`alignof`/`typeof`、
  `offsetof`、`malloc(T[N])`、`visof`、可见性枚举常量

## 剩余缺口（26 FAIL + 9 DIFF，按成因归并）

**pos 73/73 + err 36/36 + 自编译不动点**，三项目标都已达成。

已知边界（诚实清单）：

| 项 | 现状 |
|---|---|
| 诊断输出流 | 写 **stdout**（ncc 写 stderr）。原因：boot2 自身由 ncc 编译，而 ncc 只提供 `print`/`puts`，没有 stderr 通道；harness 合并两股流后判据等价 |
| 诊断规则深度 | 按语料逐族实现：可见性矩阵是 4 档简化版，所有权只跟 `flow` 源的借用/转移，`m2` 的调用实参检查只对 `const` 实参生效 |
| 错误恢复 | 出错后按行/括号跳过，不保证只报一条（`err.sh` 只要求命中期望串） |
| 未覆盖 | 语言层新特性（动态数组增长、切片运行时长度）、ASan 级别的内存安全验证、`ir-riscv64`/`ir-loongarch64` 交叉后端 |

## 能力边界（2026-11-28 复核，Windows x86-64 / tcc 0.9.27 / ir-c / ncc v0.2.3）

| 能力 | 状态 | 说明 |
|---|---|---|
| 文件读 / 写 | ✅ | `fopen/fread/fwrite/fclose` 走「未知标识符→外部符号」，tcc 连 libc |
| `getenv` | ✅ | 取输入/输出路径靠它（`BOOT_IN` / `BOOT_OUT`） |
| `main` 带参 | ✅ | `func main(argc i32, argv void)` 可编译、`argc` 真实传入；取字符串走 `argv.(void[N])[i]`（直接 `argv[i]` 仍按泛型指针拒收，需先 `.(T)`） |
| `malloc(类型[N])` | ✅ | 大缓冲必须走堆（栈帧上限 6000 字节） |
| `free` | ✅ | `free(p)` 正常生成并链接 libc `free`（`p` 为 `void*`）。语言层仍无 auto-free，不自动释放 |
| 全局标量 `var g i32` | ✅ | 编译器状态用它；**全局数组/聚合不支持**，缓冲地址存 `i64` 再取回 |
| 数组形参 | ✅ | `func f(a i32[])` / `S arr[]` 可用（2026-11-24 修：原型按指针衰减）；仅限一维，源侧既有代码仍用 `void*` 写法 |
| `void*` + 数组后缀寻址 | ✅ | `p.(i8[65536])[i]` |
| `p.(AggType).成员` | ✅ | 标量成员与**数组成员**（`p.(Buf).data[i]`）均可读写（2026-11-28 复核；见 `tests/agg_array_member`） |
| 结构体按值传参 / 返回 | ✅ | 含 `char[N]` 成员；整块复制，别把大缓冲塞结构体 |
| 互递归 | ✅ | `block ↔ stmt` 靠它 |
| 函数体 `{` 换行 | ✅ | `{` 与签名同行或换到下一行均可正确出码（2026-11-28 复核；见 `tests/brace_newline`） |
| auto-free / 可增长数组 | ❌ | 定容缓冲；当前直接不释放 |

## 编译器侧必须的修补（分支 `selfhost`，已落地）

| 编号 | 内容 |
|---|---|
| SH-1 | 声明初值可省略、无初值确定性零填充 |
| SH-2 | `link "lib"` 真正进入链接命令行 |
| **SH-3** | **`ir_to_c` 的 PARAM 收集改为从后往前取最近 nargs 条**（函数内 PARAM 超 64 后每次调用都用错实参；boot1 第一次运行即崩于此） |

## 路线图

| 阶段 | 内容 | 状态 |
|---|---|---|
| S1 | boot1 编译 N0 样例 → C → 可运行 | ✅ |
| S2 | boot2 覆盖 ncc 0.2.x 语法：pos 73/73、err 36/36 | ✅ |
| S3 | 自编译闭环：boot3 产物与 boot2 逐字节相同（不动点） | ✅ |
| S4 | 用自举链继续演进 boot 编译器本身（改动 `boot.nc` 后仍须过 FIXPOINT + 全语料） | 🟡 进行中 |

### S4 开发日志

- **2026-11-28 · 类型名值位置诊断（与 ncc 对齐）**：`boot.nc` 的 `primary` 值分支补一条
  `code_of(gi) > 0 && sym_find(gi) < 0 → "type name used as value: X"`。此前 `p N = N{7}`
  （NihaoC 无 `Type{...}` 复合字面量）会被静默出成 `N p = N;{ 7;}`——错值且不报错，正是项目
  最忌的「编译器不报错却产出不可编译/错值 C」。修复后 rc!=0 且不产出，与 ncc 的
  `undeclared variable` 判据等价。枚举成员（`GREEN`）、libc 外部符号（`fopen`/`getenv`）、
  `sizeof/malloc/.(T)` 的类型位置各走专门路径，不受影响。
  改动经完整自举验证：`boot2 → boot3 → boot4` **FIXPOINT OK**，boot3/boot4 跑 pos 73 / err 36 /
  selftest 6 全绿。见 `probes/probe_type_as_value.nc`。

- **2026-11-28 · 实现未支持语法 `u64` 类型**：`code_of` 的标量映射缺 `u64`，导致 `x u64 = …`、
  `sizeof(u64)`、`u64` 数组在 boot2 下直接崩（ncc 侧正常，按 8 字节存为 `int64_t`）。补一行
  `if txt_eq(i, "u64") == 1 { return 4 }`，复用 `i64` 的码 4（`ctype→int64_t`、`size_of_code→8`），
  与 ncc 逐字节等价（`sizeof(u64)=8`、`18446744073709551615` 打印 `-1`）。
  经完整自举验证：`boot2 → boot3 → boot4` **FIXPOINT OK**，boot3/boot4 跑 pos 73 / err 36 /
  selftest 7 全绿。见 `tests/u64_type.nc`。