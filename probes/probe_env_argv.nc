module main
use stdio

/* 探针：main 带参（argc 真实传入）+ getenv 取环境变量
 * 结论：argc 可用；argv[i] 取字符串未走通（见 README），文件名建议走 getenv。 */

func main(argc i32, argv void) {
    print("argc=%d\n", argc)
    e void = getenv("PATH")
    if e == 0 {
        puts("env missing")
    } else {
        puts("env ok")
    }
}
