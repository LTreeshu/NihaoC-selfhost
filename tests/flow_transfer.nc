module main
use stdio

/* 自举回归：flow→flow 所有权转移（§12.1）——仅接收方退出释放。
 * 若源与接收方都释放（双释放）程序会崩，输出缺失即 FAIL。 */
func main() {
    flow a void = malloc(i8[8])
    a.(i8[8])[0] = 79
    a.(i8[8])[1] = 0
    flow b void = a
    puts(b)
    print("x=%d\n", 1)
}
