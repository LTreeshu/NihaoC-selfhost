# NihaoC 自举编译器（自举工作区）

用 NihaoC 自己写 NihaoC 编译器。本目录**独立于** NihaoC 仓库：编译器侧的改动走仓库内的
本地分支 `selfhost`（不推送、不并入 `PB`），自举编译器本体在这里演进。

- 目标平台：`-backend ir-c`（唯一带宿主 libc 与文件系统的可信链路）
- 编译器侧准备记录：`NihaoC/docs/SELFHOST.md`（分支 `selfhost`）
- 当前阶段：**S1 达成；S2 达成** —— `boot2` 已能吃下 ncc 自带 **全部 pos 用例**
  （73 份有 `.expect` 的全通过，0 FAIL；另 2 份模块型无期望，见「覆盖率」）

## 目录

```
NihaoC-selfhost/
├── README.md          本文件
├── check.sh           S1 回归：编 boot1 → 跑样例 → tcc → 比对期望
├── coverage.sh        S2 度量：用 ncc 自带 pos 用例喂 boot2，逐份比对 .expect
├── coverage.log       最近一次度量明细（OK / DIFF / FAIL 逐份）
├── boot1/boot.nc      Stage 1：N0 子集 → C（约 380 行）
├── boot2/boot.nc      Stage 2：NihaoC 语法 → C（token 化 + 直接出码，约 1900 行）
├── samples/*.n0       N0 样例 + *.expected
└── probes/*.nc        能力探针（每条对应一处实测边界）
```

## 怎么跑

```bash
export NIHAO_TCC_DIR="D:/Program Files/tcc"   # Windows
export NCC=../NihaoC/ncc/build/ncc.exe        # 可覆盖

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

**pos 语料（73 份带 `.expect`）已全部通过**，没有剩余 FAIL/DIFF。

下一步的真实缺口不在 pos，而在两处：

| 方向 | 说明 |
|---|---|
| `tests/err` 诊断语料（36 份） | 目前只做「能编对」，没做「该报错时报错」；需要把 ncc 的诊断口径搬过来（越界、const 写、所有权、容量等） |
| S3 自编译 | `boot2` 用到的语法已全部覆盖，下一步是把 `boot2` 自身源码喂给 `boot2`，产出可自举的 `boot3` |

## 能力边界（2026-11-21 实测，Windows x86-64 / tcc 0.9.27 / ir-c）

| 能力 | 状态 | 说明 |
|---|---|---|
| 文件读 / 写 | ✅ | `fopen/fread/fwrite/fclose` 走「未知标识符→外部符号」，tcc 连 libc |
| `getenv` | ✅ | 取输入/输出路径靠它（`BOOT_IN` / `BOOT_OUT`） |
| `main` 带参 | ⚠️ | `func main(argc i32, argv void)` 可编译、`argc` 真实传入；取 `argv[i]` 字符串未走通 |
| `malloc(类型[N])` | ✅ | 大缓冲必须走堆（栈帧上限 6000 字节） |
| `free` | ❌ 不可调 | `void*` 在产物 C 里是 `int64_t`，tcc 的 `free(void*)` 原型拒收 |
| 全局标量 `var g i32` | ✅ | 编译器状态用它；**全局数组/聚合不支持**，缓冲地址存 `i64` 再取回 |
| 数组形参 | ❌ | `func f(a char[])` 解析失败 → 用 `void*` |
| `void*` + 数组后缀寻址 | ✅ | `p.(i8[65536])[i]` |
| `p.(AggType).成员` | ⚠️ | 标量成员可读写；数组成员经 `.(AggType)` 不支持 |
| 结构体按值传参 / 返回 | ✅ | 含 `char[N]` 成员；整块复制，别把大缓冲塞结构体 |
| 互递归 | ✅ | `block ↔ stmt` 靠它 |
| 函数体 `{` 换行 | ❌ | `{` 必须与签名同行 |
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
| S2 | boot2 覆盖 ncc 0.2.x 语法，pos 用例通过率作为度量 | 🔄 47/75 |
| S3 | boot2 编译自身（自举闭环），与 ncc 输出对齐 | 未开始 |