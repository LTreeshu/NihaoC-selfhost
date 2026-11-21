module main
use stdio

/* boot1 —— 自举编译器 Stage 1（N0 → C）
 *
 * N0 是 NihaoC 的极小子集：func / 声明 / 赋值 / if-else / while / return /
 * puts / print。输出等价 C（变量统一 int64_t），交 tcc 编译为可执行文件。
 *
 * 约束（见 ../README.md）：
 *   - 数组形参不支持 → 所有缓冲一律 void* 传入，用 `p.(i8[N])[i]` 寻址；
 *   - 函数体 `{` 必须与签名同行；
 *   - void* 变量在产物 C 里是 int64_t，tcc 内建 free(void*) 原型会拒收 → 不调 free；
 *   - 无 growable 数组 → 缓冲定容，溢出即止（Stage 1 限制）。
 *
 * 输入：当前目录 input.n0     输出：当前目录 output.c
 */

var gpos i32
var gsrcn i32
var gout i32

/* ---------- 字符类 ---------- */


func is_space(c i32) i32 {
    if c == 32 { return 1 }
    if c == 10 { return 1 }
    if c == 9 { return 1 }
    if c == 13 { return 1 }
    return 0
}

func is_alpha(c i32) i32 {
    if c >= 97 {
        if c <= 122 { return 1 }
    }
    if c >= 65 {
        if c <= 90 { return 1 }
    }
    if c == 95 { return 1 }
    return 0
}

func is_digit(c i32) i32 {
    if c >= 48 {
        if c <= 57 { return 1 }
    }
    return 0
}

/* ---------- 读源码 ---------- */

func at(src void, i i32) i32 {
    if i < 0 { return 0 }
    if i >= gsrcn { return 0 }
    return src.(i8[65536])[i]
}

func peekc(src void) i32 {
    return at(src, gpos)
}

func skip_ws(src void) {
    while gpos < gsrcn {
        c i32 = at(src, gpos)
        if is_space(c) == 0 { return }
        gpos = gpos + 1
    }
}

func kwlen(kw void) i32 {
    k i32 = 0
    while kw.(i8[64])[k] != 0 {
        k = k + 1
    }
    return k
}

/* 关键字匹配：整词匹配（后面不能接标识符字符），匹配则前进 */
func match_kw(src void, kw void) i32 {
    n i32 = kwlen(kw)
    k i32 = 0
    while k < n {
        if at(src, gpos + k) != kw.(i8[64])[k] { return 0 }
        k = k + 1
    }
    c i32 = at(src, gpos + n)
    if is_alpha(c) == 1 { return 0 }
    if is_digit(c) == 1 { return 0 }
    gpos = gpos + n
    return 1
}

/* ---------- 写 C ---------- */

func ap(out void, ch i32) {
    if gout >= 262140 { return }
    out.(i8[262144])[gout] = ch
    gout = gout + 1
}

func aps(out void, s void) {
    k i32 = 0
    while s.(i8[256])[k] != 0 {
        ap(out, s.(i8[256])[k])
        k = k + 1
    }
}

func copy_range(src void, out void, a i32, b i32) {
    p i32 = a
    while p < b {
        ap(out, at(src, p))
        p = p + 1
    }
}

func copy_ident(src void, out void) {
    while 1 == 1 {
        c i32 = peekc(src)
        if is_alpha(c) == 1 {
            ap(out, c)
            gpos = gpos + 1
        } else {
            if is_digit(c) == 1 {
                ap(out, c)
                gpos = gpos + 1
            } else {
                return
            }
        }
    }
}

/* 原样搬运一段表达式：到行尾 / '{' / '}' / ';' 为止；字符串内的这些字符不算终止 */
func copy_expr(src void, out void) {
    ins i32 = 0
    while gpos < gsrcn {
        c i32 = peekc(src)
        if ins == 0 {
            if c == 10 { return }
            if c == 123 { return }
            if c == 125 { return }
            if c == 59 { return }
        }
        if c == 34 {
            if ins == 0 {
                ins = 1
            } else {
                ins = 0
            }
        }
        ap(out, c)
        gpos = gpos + 1
    }
}

func is_type_kw(src void) i32 {
    if match_kw(src, "i64") == 1 { return 1 }
    if match_kw(src, "i32") == 1 { return 1 }
    if match_kw(src, "i16") == 1 { return 1 }
    if match_kw(src, "i8") == 1 { return 1 }
    if match_kw(src, "u32") == 1 { return 1 }
    if match_kw(src, "u16") == 1 { return 1 }
    if match_kw(src, "u8") == 1 { return 1 }
    if match_kw(src, "char") == 1 { return 1 }
    if match_kw(src, "f64") == 1 { return 1 }
    if match_kw(src, "f32") == 1 { return 1 }
    return 0
}

/* ---------- 语法：语句 / 块 / 函数 ---------- */

func block(src void, out void) {
    while 1 == 1 {
        skip_ws(src)
        if gpos >= gsrcn { return }
        if peekc(src) == 125 {
            gpos = gpos + 1
            return
        }
        stmt(src, out)
    }
}

func stmt(src void, out void) {
    skip_ws(src)
    if gpos >= gsrcn { return }
    c i32 = peekc(src)
    if c == 125 { return }

    if match_kw(src, "if") == 1 {
        aps(out, "if (")
        copy_expr(src, out)
        aps(out, ") {\n")
        if peekc(src) == 123 { gpos = gpos + 1 }
        block(src, out)
        skip_ws(src)
        if match_kw(src, "else") == 1 {
            aps(out, "} else {\n")
            skip_ws(src)
            if peekc(src) == 123 { gpos = gpos + 1 }
            block(src, out)
        }
        aps(out, "}\n")
        return
    }

    if match_kw(src, "while") == 1 {
        aps(out, "while (")
        copy_expr(src, out)
        aps(out, ") {\n")
        if peekc(src) == 123 { gpos = gpos + 1 }
        block(src, out)
        aps(out, "}\n")
        return
    }

    if match_kw(src, "print") == 1 {
        aps(out, "printf")
        copy_expr(src, out)
        aps(out, ";\n")
        return
    }

    if match_kw(src, "return") == 1 {
        aps(out, "return ")
        skip_ws(src)
        copy_expr(src, out)
        aps(out, ";\n")
        return
    }

    if is_alpha(c) == 1 {
        st i32 = gpos
        while 1 == 1 {
            cc i32 = at(src, gpos)
            if is_alpha(cc) == 1 {
                gpos = gpos + 1
            } else {
                if is_digit(cc) == 1 {
                    gpos = gpos + 1
                } else {
                    break
                }
            }
        }
        en i32 = gpos
        skip_ws(src)
        if is_type_kw(src) == 1 {
            aps(out, "int64_t ")
            copy_range(src, out, st, en)
            ap(out, 32)
            copy_expr(src, out)
            aps(out, ";\n")
            return
        }
        gpos = st
        copy_expr(src, out)
        aps(out, ";\n")
        return
    }

    /* 其他 token：吞到行尾，保持可继续解析 */
    while gpos < gsrcn {
        if peekc(src) == 10 { break }
        gpos = gpos + 1
    }
}

func funcdef(src void, out void) {
    skip_ws(src)
    aps(out, "int64_t ")
    copy_ident(src, out)
    skip_ws(src)
    ap(out, 40)
    if peekc(src) == 40 { gpos = gpos + 1 }   /* 关键：消费 '('，否则参数循环空转 */
    skip_ws(src)
    while gpos < gsrcn {
        if peekc(src) == 41 { break }
        aps(out, "int64_t ")
        copy_ident(src, out)
        skip_ws(src)
        is_type_kw(src)
        skip_ws(src)
        if peekc(src) == 44 {
            ap(out, 44)
            ap(out, 32)
            gpos = gpos + 1
        }
        skip_ws(src)
    }
    if peekc(src) == 41 { gpos = gpos + 1 }
    ap(out, 41)
    skip_ws(src)
    is_type_kw(src)
    skip_ws(src)
    if peekc(src) == 123 { gpos = gpos + 1 }
    aps(out, " {\n")
    block(src, out)
    /* 统一补 return 0;：N0 的 main 通常没有显式 return，C 里 fall-off-end
     * 的返回值是垃圾（实测退出码 8）。对其它函数是一条不可达的默认返回。 */
    aps(out, "return 0;\n")
    aps(out, "}\n\n")
}

func prog(src void, out void) {
    aps(out, "#include <stdio.h>\n#include <stdint.h>\n\n")
    while gpos < gsrcn {
        skip_ws(src)
        if gpos >= gsrcn { break }
        if match_kw(src, "func") == 1 {
            funcdef(src, out)
        } else {
            while gpos < gsrcn {
                if peekc(src) == 10 { break }
                gpos = gpos + 1
            }
        }
    }
}

/* ---------- 驱动 ---------- */

func main() {
    src void = malloc(i8[65536])
    out void = malloc(i8[262144])
    gpos = 0
    gout = 0
    gsrcn = 0

    f void = fopen("input.n0", "r")
    if f == 0 {
        puts("boot1: cannot open input.n0")
        return
    }
    gsrcn = fread(src, 1, 65535, f)
    fclose(f)

    prog(src, out)

    o void = fopen("output.c", "w")
    if o == 0 {
        puts("boot1: cannot create output.c")
        return
    }
    fwrite(out, 1, gout, o)
    fclose(o)

    print("boot1: %d bytes -> output.c\n", gout)

    /* 不调 free()：void* 在产物 C 里是 int64_t，tcc 内建 free(void*) 原型拒收
     * （error: cannot cast from/to void）。Stage 1 进程随即退出，泄漏无影响。 */
}
