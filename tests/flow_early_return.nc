module main
use stdio

/* 自举回归：提前 return 生成退出释放，且每条运行路径恰释放一次（§11.1）。
 * return 路径先求值后释放（__nrv 重构）；不走 return 的路径由其自身出口释放。
 * 任一路径双释放即崩，输出缺失即 FAIL。 */
func pick(flag i32) i32 {
    p void = malloc(i8[8])
    p.(i8[8])[0] = 80
    p.(i8[8])[1] = 0
    if flag == 1 {
        return 1
    }
    puts(p)
    return 0
}

func main() {
    a i32 = pick(1)
    b i32 = pick(0)
    print("a=%d b=%d\n", a, b)
}
