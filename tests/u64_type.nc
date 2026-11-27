module main
use stdio

/* 自举回归：u64 类型（此前 boot2 的 code_of 缺 u64，声明/sizeof 直接崩）。
 * ncc 把 u64 按 8 字节存为 int64_t；boot2 现映射到同一码，输出与 ncc 逐字节一致。 */
func main() {
    a u64 = 1000000000000
    b u64 = 7
    c u64 = a + b
    print("c=%d sz=%d\n", c, sizeof(u64))
    arr u64[3] = {1, 2, 3}
    print("arr1=%d len=%d\n", arr[1], len(arr))
    d u64 = 18446744073709551615
    print("max=%d\n", d)
}
