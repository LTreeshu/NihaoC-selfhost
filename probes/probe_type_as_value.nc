module main
use stdio

/* 探针：类型名出现在「值位置」——NihaoC 没有 Type{...} 复合字面量。
 * ncc 侧：`p N = N{7}` 报 "undeclared variable 'N'"。
 * boot2 侧（2026-11-28 修复）：此前会静默把类型名当未知标识符出成外部符号
 *   （产物 C 形如 `N p = N;{ 7;}`，错值且不报错）；
 *   现补一条诊断 "type name used as value: N"，rc!=0 且不产出，与 ncc 判据对齐。
 * 合法用法不受影响：枚举成员（如 GREEN）、外部 libc 符号（fopen/getenv）、
 *   sizeof/malloc/.(T) 等类型位置各自走专门出码路径，均不经此值位置分支。 */

N struct { v i32 }

func main() {
    p N = N{7}
    print("v=%d\n", p.v)
}
