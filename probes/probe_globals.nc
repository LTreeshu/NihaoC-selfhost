module main
use stdio

var gsrc i64
var gpos i32

func rd(i i32) i32 {
    p void = gsrc
    return p.(i8[64])[i]
}

func main() {
    b void = malloc(i8[64])
    b.(i8[64])[0] = 65
    b.(i8[64])[1] = 0
    gsrc = b
    gpos = 1
    print("rd=%d pos=%d\n", rd(0), gpos)
    q void = gsrc
    puts(q)
}
