module main
use stdio

/* 自举回归：堆分配 + free（malloc 后可读改，free 后再 malloc 复用）
 * 覆盖 README 曾标 ❌ 的 `free`：现 ncc v0.2.3 / boot2 已可正常生成并链接 libc free。 */
func main() {
    p void = malloc(i8[32])
    p.(i8[32])[0] = 72
    p.(i8[32])[1] = 0
    puts(p)
    free(p)
    q void = malloc(i8[16])
    q.(i8[16])[0] = 75
    q.(i8[16])[1] = 0
    puts(q)
    free(q)
    puts("heap ok")
}
