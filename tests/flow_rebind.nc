module main
use stdio

/* 自举回归：整变量重绑定按新右值重判（§11.1）——绑字面量后退出不 free。
 * 若仍按旧 malloc 来源释放只读段，程序崩，输出缺失即 FAIL。 */
func main() {
    flow p void = malloc(i8[8])
    p = "rebound"
    puts(p)
    q void = malloc(i8[8])
    q.(i8[8])[0] = 75
    q.(i8[8])[1] = 0
    puts(q)
}
