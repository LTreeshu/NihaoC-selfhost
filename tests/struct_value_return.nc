module main
use stdio

/* 探针 B：按值返回 struct */
Pt struct {
    x i32
    y i32
}

func mk(a i32, b i32) Pt {
    p Pt = { a, b }
    return p
}

func main() {
    q Pt = mk(1, 2)
    if q.x + q.y == 3 { puts("struct value return ok") } else { puts("struct value return bad") }
    return
}
