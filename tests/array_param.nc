module main
use stdio

/* 探针 A：数组形参（README 记为不支持，实测确认） */
func sum(a i32[], n i32) i32 {
    var s i32 = 0
    var i i32 = 0
    while i < n { s = s + a[i]  i = i + 1 }
    return s
}

func main() {
    b i32[3] = { 1, 2, 3 }
    if sum(b, 3) == 6 { puts("array param ok") } else { puts("array param bad") }
    return
}
