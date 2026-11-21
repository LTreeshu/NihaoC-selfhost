module main
use stdio

/* 探针：互递归（boot1 的 block <-> stmt 依赖它） */

func even(n i32) i32 {
    if n == 0 { return 1 }
    return odd(n - 1)
}

func odd(n i32) i32 {
    if n == 0 { return 0 }
    return even(n - 1)
}

func main() {
    print("even10=%d\n", even(10))
}
