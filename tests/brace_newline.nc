module main
use stdio

/* 自举回归：函数体 `{` 换行到签名下一行
 * 覆盖 README 曾标 ❌ 的「`{` 必须与签名同行」：现两种写法均可正确出码。 */
func add(a i32, b i32) i32
{
    return a + b
}

func main()
{
    s i32 = add(20, 22)
    print("sum=%d\n", s)
}
