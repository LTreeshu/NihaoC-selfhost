module main
use stdio

/* 自举回归：flow 返回值由调用方接管并退出释放（§7.2/§11.1）。
 * 若被调方与调用方都释放（双释放）程序崩，输出缺失即 FAIL。 */
func mk() flow void {
    p void = malloc(i8[8])
    p.(i8[8])[0] = 77
    p.(i8[8])[1] = 0
    return p
}

func main() {
    r void = mk()
    puts(r)
    print("x=%d\n", 1)
}
