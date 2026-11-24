module main
use stdio

/* 探针 C：局部数组在函数里返回指针（越界生命期）+ 结构体数组形参 */
S struct {
    k i32
}

func bump(arr S[], n i32) {
    var i i32 = 0
    while i < n {
        arr[i].k = arr[i].k + 1
        i = i + 1
    }
    return
}

func main() {
    xs S[3] = { {1}, {2}, {3} }
    bump(xs, 3)
    if xs[0].k == 2 && xs[2].k == 4 { puts("struct array param ok") } else { puts("struct array param bad") }
    return
}
