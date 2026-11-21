module main
use stdio

/* 探针：堆上的上下文 + void* 参数 + 聚合标量成员访问
 * 结论：malloc(Ctx) 与 `c.(Ctx).n` 可用；但 `c.(Ctx).buf[i]`（聚合数组成员经 .(T)）不支持。 */

Ctx struct { n i32 }

func bump(c void) {
    c.(Ctx).n = c.(Ctx).n + 1
}

func main() {
    p void = malloc(Ctx)
    p.(Ctx).n = 41
    bump(p)
    print("n=%d\n", p.(Ctx).n)

    b void = malloc(i8[64])
    b.(i8[64])[0] = 65
    b.(i8[64])[1] = 0
    puts(b)
}
