module main
use stdio

/* 自举回归：聚合数组成员经 `.(T)` 读写
 * 覆盖 README 曾标 ⚠️ 的 `c.(AggType).buf[i]`：现可正常落位并读回。 */
Buf struct {
    data i8[8]
    n i32
}

func main() {
    p void = malloc(Buf)
    p.(Buf).data[0] = 72
    p.(Buf).data[1] = 73
    p.(Buf).data[2] = 0
    p.(Buf).n = 2
    puts(p.(Buf).data)
    print("n=%d\n", p.(Buf).n)
}
