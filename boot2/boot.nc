module main
use stdio

/* boot2 —— 自举编译器 Stage 2（NihaoC → C）
 *
 * 目标：把 ncc/tests/pos 下的 NihaoC 用例原样吃进来，产出等价 C，交 tcc 编译。
 * 手段：token 化 + 直接出 C（无 AST），符号表只记「名字 / 类型码 / 维数 / 指向类型 / 可见性」。
 *
 * 平台约束（见 ../README.md）：
 *   - 全局只能放标量 → 所有缓冲用 `var gxxx i64` 存地址，用时 `p void = gxxx` 取回；
 *   - 数组形参不支持 → 一律 void* + `.(i8[N])[i]`；
 *   - 无 auto-free；函数体 `{` 必须与签名同行。
 *
 * 输入：环境变量 BOOT_IN（缺省 input.n0）  输出：BOOT_OUT（缺省 output.c）
 */

/* ================= 全局状态 ================= */

var gsrc i64        /* 源码缓冲地址 */
var gsrcn i32
var gtk i64         /* token 数组地址：每 token 3 个 i32（kind,start,len） */
var gntk i32
var gi i32          /* 当前 token 下标 */
var gout i64        /* 输出缓冲地址 */
var goutn i32
var gerr i32

var gn i32          /* 符号数 */
var gnames i64      /* 符号名 token 下标（i32[256]） */
var gtypes i64      /* 类型码 */
var gdims i64       /* 数组维数（0=标量，1=一维…） */
var gpt i64         /* 指向类型码（0=未知） */
var gvis i64        /* 可见性 0..4 */

var gnt i32         /* 聚合类型数 */
var gtn i64         /* 聚合名 token */
var gtk2 i64        /* 种类 1=struct 2=union 3=enum */

var gloop i32       /* 循环嵌套深度 */
var gisn i64        /* 每层 while 的 __is 编号 */
var gret i32        /* 当前函数返回类型码 */
var gseq i32        /* 临时名序号 */
var gslm i32
var gsbtok i32
var gsafter i32
var gslbs i32
var gslbe i32
var gslls i32
var gslle i32
var gmc i32
var gmagg i64
var gmidx i64
var gmname i64
var gmcode i64
var gmarray i64
var gmdef i64
var gdl i64
var gdn i32
var gmbit i64
var gretvis i32
var gmsrc i64
var gmtk i64
var gskipdefs i32
var gtop i32
var ginitn i32
var giname i64
var gis i64
var gie i64
var glastis i32
var gfirst i32
var gslice i64
var gmdef2 i64
var gsel i64
var gmdn i32
var gmd i64
var gstate i64
var glastfrz i32

/* ================= 词法 ================= */

func is_id0(c i32) i32 {
    if c >= 65 {
        if c <= 90 { return 1 }
    }
    if c >= 97 {
        if c <= 122 { return 1 }
    }
    if c == 95 { return 1 }
    return 0
}

func is_id1(c i32) i32 {
    if is_id0(c) == 1 { return 1 }
    if c >= 48 {
        if c <= 57 { return 1 }
    }
    return 0
}

func is_sp(c i32) i32 {
    if c == 32 { return 1 }
    if c == 9 { return 1 }
    if c == 13 { return 1 }
    return 0
}

func sch(i i32) i32 {
    s void = gsrc
    if i < 0 { return 0 }
    if i >= gsrcn { return 0 }
    return s.(i8[524288])[i]
}

func put_tok(kind i32, st i32, ln i32) {
    if gntk * 3 + 2 >= 1048576 { return }
    t void = gtk
    t.(i32[1048576])[gntk * 3] = kind
    t.(i32[1048576])[gntk * 3 + 1] = st
    t.(i32[1048576])[gntk * 3 + 2] = ln
    gntk = gntk + 1
}

/* 多字符运算符：按最长匹配，返回长度（0=不是本符号） */
func m2(i i32, a i32, b i32) i32 {
    if sch(i) == a {
        if sch(i + 1) == b { return 2 }
    }
    return 0
}

func m3(i i32, a i32, b i32, c i32) i32 {
    if sch(i) == a {
        if sch(i + 1) == b {
            if sch(i + 2) == c { return 3 }
        }
    }
    return 0
}

func is_dg(c i32) i32 {
    if c >= 48 {
        if c <= 57 { return 1 }
    }
    return 0
}

func lex() {
    i i32 = 0
    while i < gsrcn {
        c i32 = sch(i)
        if is_sp(c) == 1 {
            i = i + 1
        } else if c == 10 {
            put_tok(7, i, 1)
            i = i + 1
        } else if c == 47 {
            if sch(i + 1) == 47 {
                while i < gsrcn {
                    if sch(i) == 10 { break }
                    i = i + 1
                }
            } else if sch(i + 1) == 42 {
                i = i + 2
                while i < gsrcn {
                    if sch(i) == 42 {
                        if sch(i + 1) == 47 {
                            i = i + 2
                            break
                        }
                    }
                    i = i + 1
                }
            } else if sch(i + 1) == 61 {
                put_tok(6, i, 2)
                i = i + 2
            } else {
                put_tok(6, i, 1)
                i = i + 1
            }
        } else if is_id0(c) == 1 {
            st i32 = i
            while i < gsrcn {
                if is_id1(sch(i)) == 0 { break }
                i = i + 1
            }
            put_tok(1, st, i - st)
        } else if is_dg(c) == 1 {
            st2 i32 = i
            hex i32 = 0
            if c == 48 {
                if sch(i + 1) == 120 { hex = 1 i = i + 2 }
                if sch(i + 1) == 88 { hex = 1 i = i + 2 }
                if sch(i + 1) == 98 { hex = 2 i = i + 2 }
            }
            while i < gsrcn {
                cc i32 = sch(i)
                if is_dg(cc) == 1 {
                    i = i + 1
                } else if hex == 1 {
                    if cc >= 97 { if cc <= 102 { i = i + 1 } else { break } }
                    else if cc >= 65 { if cc <= 70 { i = i + 1 } else { break } }
                    else { break }
                } else if cc == 46 {
                    if sch(i + 1) == 46 { break }
                    i = i + 1
                } else if hex == 2 {
                    if cc == 48 { i = i + 1 } else if cc == 49 { i = i + 1 } else { break }
                } else if cc == 101 {
                    /* 指数 e[+-]?digits */
                    i = i + 1
                    if sch(i) == 43 { i = i + 1 }
                    if sch(i) == 45 { i = i + 1 }
                } else if cc == 69 {
                    i = i + 1
                    if sch(i) == 43 { i = i + 1 }
                    if sch(i) == 45 { i = i + 1 }
                } else {
                    break
                }
            }
            put_tok(2, st2, i - st2)
        } else if c == 34 {
            st3 i32 = i
            i = i + 1
            while i < gsrcn {
                if sch(i) == 92 { i = i + 2 }
                else if sch(i) == 34 { i = i + 1 break }
                else { i = i + 1 }
            }
            put_tok(4, st3, i - st3)
        } else if c == 39 {
            st4 i32 = i
            i = i + 1
            while i < gsrcn {
                if sch(i) == 92 { i = i + 2 }
                else if sch(i) == 39 { i = i + 1 break }
                else { i = i + 1 }
            }
            put_tok(5, st4, i - st4)
        } else {
            n3 i32 = m3(i, 46, 46, 46)
            if n3 == 3 {
                put_tok(6, i, 3)
                i = i + 3
            } else {
                n2 i32 = 0
                if c == 45 { n2 = m2(i, 45, 62) }
                if n2 == 0 { if c == 61 { n2 = m2(i, 61, 61) } }
                if n2 == 0 { if c == 33 { n2 = m2(i, 33, 61) } }
                if n2 == 0 { if c == 60 { n2 = m2(i, 60, 61) } }
                if n2 == 0 { if c == 62 { n2 = m2(i, 62, 61) } }
                if n2 == 0 { if c == 38 { n2 = m2(i, 38, 38) } }
                if n2 == 0 { if c == 124 { n2 = m2(i, 124, 124) } }
                if n2 == 0 { if c == 43 { n2 = m2(i, 43, 43) } }
                if n2 == 0 { if c == 45 { n2 = m2(i, 45, 45) } }
                if n2 == 0 { if c == 60 { n2 = m2(i, 60, 60) } }
                if n2 == 0 { if c == 62 { n2 = m2(i, 62, 62) } }
                if n2 == 0 { if c == 43 { n2 = m2(i, 43, 61) } }
                if n2 == 0 { if c == 45 { n2 = m2(i, 45, 61) } }
                if n2 == 0 { if c == 42 { n2 = m2(i, 42, 61) } }
                if n2 == 0 { if c == 47 { n2 = m2(i, 47, 61) } }
                if n2 == 0 { if c == 37 { n2 = m2(i, 37, 61) } }
                if n2 == 0 { if c == 124 { n2 = m2(i, 124, 61) } }
                if n2 == 0 { if c == 38 { n2 = m2(i, 38, 61) } }
                if n2 == 0 { if c == 94 { n2 = m2(i, 94, 61) } }
                if n2 == 0 { if c == 46 { if sch(i + 1) == 46 { n2 = 2 } } }
                if n2 == 0 { if c == 61 { n2 = m2(i, 61, 62) } }
                if n2 == 0 { if c == 58 { n2 = m2(i, 58, 61) } }
                if n2 == 0 { if c == 63 { n2 = m2(i, 63, 61) } }
                if n2 == 0 { if c == 63 { n2 = m2(i, 63, 46) } }
                if n2 == 0 { n2 = 1 }
                put_tok(6, i, n2)
                i = i + n2
            }
        }
    }
    put_tok(8, gsrcn, 0)
}

/* ================= token 访问 ================= */

func tk_kind(i i32) i32 {
    t void = gtk
    if i < 0 { return 8 }
    if i >= gntk { return 8 }
    return t.(i32[1048576])[i * 3]
}

func tk_st(i i32) i32 {
    t void = gtk
    return t.(i32[1048576])[i * 3 + 1]
}

func tk_ln(i i32) i32 {
    t void = gtk
    return t.(i32[1048576])[i * 3 + 2]
}

func ck() i32 {
    return tk_kind(gi)
}

func adv() {
    gi = gi + 1
}

func skip_nl() {
    while 1 == 1 {
        if tk_kind(gi) != 7 { return }
        gi = gi + 1
    }
}

/* 当前 token 是否是指定文本（标识符或标点都可比） */
func txt_eq(i i32, s void) i32 {
    n i32 = 0
    while s.(i8[32])[n] != 0 {
        n = n + 1
    }
    if tk_ln(i) != n { return 0 }
    st i32 = tk_st(i)
    k i32 = 0
    while k < n {
        if sch(st + k) != s.(i8[32])[k] { return 0 }
        k = k + 1
    }
    return 1
}

func tok_eq(a i32, b i32) i32 {
    if tk_ln(a) != tk_ln(b) { return 0 }
    if tk_ln(a) == 0 { return 1 }
    sa i32 = tk_st(a)
    sb i32 = tk_st(b)
    k i32 = 0
    while k < tk_ln(a) {
        if sch(sa + k) != sch(sb + k) { return 0 }
        k = k + 1
    }
    return 1
}

func is_p(s void) i32 {
    if ck() != 6 { return 0 }
    return txt_eq(gi, s)
}

func eat_p(s void) i32 {
    if is_p(s) == 1 {
        adv()
        return 1
    }
    return 0
}

func need_p(s void) {
    /* 解析恢复：只推进，不计入诊断数（诊断数只由 emsg 记） */
    if is_p(s) == 1 { adv() }
}

func is_kw(s void) i32 {
    if ck() != 1 { return 0 }
    return txt_eq(gi, s)
}

/* ================= 输出 ================= */

/* 报错：消息打 stdout（err.sh 合并 2>&1 判据），并记错误数 */
func tok_cstr(i i32) {
    st i32 = tk_st(i)
    n i32 = tk_ln(i)
    k i32 = 0
    o void = gout
    while k < n {
        o.(i8[524288])[k] = sch(st + k)
        k = k + 1
    }
    o.(i8[524288])[n] = 0
}

func emsg(s void) {
    print("错误: %s\n", s)
    gerr = gerr + 1
}

func emsg1(pre void, tok i32) {
    tok_cstr(tok)
    print("错误: %s%s\n", pre, gout)
    gerr = gerr + 1
}

func ec(ch i32) {
    o void = gout
    if goutn >= 524280 { return }
    o.(i8[524288])[goutn] = ch
    goutn = goutn + 1
}

func eo(s void) {
    k i32 = 0
    while s.(i8[128])[k] != 0 {
        ec(s.(i8[128])[k])
        k = k + 1
    }
}

func eol() {
    ec(10)
}

func etk(i i32) {
    st i32 = tk_st(i)
    n i32 = tk_ln(i)
    k i32 = 0
    while k < n {
        ec(sch(st + k))
        k = k + 1
    }
}

func enum_i(v i32) {
    if v < 0 {
        ec(45)
        v = 0 - v
    }
    if v >= 10 { enum_i(v / 10) }
    ec(48 + v % 10)
}

func ocopy(a i32, b i32) {
    o void = gout
    k i32 = a
    while k < b {
        ec(o.(i8[524288])[k])
        k = k + 1
    }
}

func espace() {
    ec(32)
}

/* ================= 符号表 ================= */

func sym_add(nt i32, code i32, dims i32, pt i32, vis i32) i32 {
    a void = gnames
    b void = gtypes
    c void = gdims
    e void = gpt
    f void = gvis
    a.(i32[512])[gn] = nt
    b.(i32[512])[gn] = code
    c.(i32[512])[gn] = dims
    e.(i32[512])[gn] = pt
    f.(i32[512])[gn] = vis
    sc void = gslice
    sc.(i32[512])[gn] = 0
    gn = gn + 1
    return gn - 1
}

func gmd_name(k i32) i32 {
    a void = gmd
    return a.(i32[48])[k * 3]
}

func gmd_s(k i32) i32 {
    a void = gmd
    return a.(i32[48])[k * 3 + 1]
}

func gmd_e(k i32) i32 {
    a void = gmd
    return a.(i32[48])[k * 3 + 2]
}

func gmd_set(k i32, nm i32, st i32, en i32) {
    a void = gmd
    a.(i32[48])[k * 3] = nm
    a.(i32[48])[k * 3 + 1] = st
    a.(i32[48])[k * 3 + 2] = en
}

func gdims_set(i i32, v i32) {
    c8 void = gdims
    c8.(i32[512])[i] = v
}

func sym_find(nt i32) i32 {
    a void = gnames
    k i32 = gn - 1
    while k >= 0 {
        if tok_eq(a.(i32[512])[k], nt) == 1 { return k }
        k = k - 1
    }
    return -1
}

func sym_code(i i32) i32 {
    b void = gtypes
    return b.(i32[512])[i]
}

func sym_dims(i i32) i32 {
    c void = gdims
    return c.(i32[512])[i]
}

func sym_pt(i i32) i32 {
    e void = gpt
    return e.(i32[512])[i]
}

func sym_set_pt(i i32, v i32) {
    e void = gpt
    e.(i32[512])[i] = v
}

func sym_vis(i i32) i32 {
    f void = gvis
    return f.(i32[512])[i]
}

/* ================= 类型 ================= */

func agg_add(nt i32, kind i32) i32 {
    a void = gtn
    b void = gtk2
    a.(i32[128])[gnt] = nt
    b.(i32[128])[gnt] = kind
    gnt = gnt + 1
    return gnt - 1
}

func agg_find(nt i32) i32 {
    a void = gtn
    k i32 = 0
    while k < gnt {
        if tok_eq(a.(i32[128])[k], nt) == 1 { return k }
        k = k + 1
    }
    return -1
}

/* 类型 token 下标 → 类型码；非类型返回 0。
 * 标量 1..13；聚合 20+id */
func code_of(i i32) i32 {
    if tk_kind(i) != 1 { return 0 }
    if txt_eq(i, "i8") == 1 { return 1 }
    if txt_eq(i, "i16") == 1 { return 2 }
    if txt_eq(i, "i32") == 1 { return 3 }
    if txt_eq(i, "i64") == 1 { return 4 }
    if txt_eq(i, "u8") == 1 { return 5 }
    if txt_eq(i, "u16") == 1 { return 6 }
    if txt_eq(i, "u32") == 1 { return 7 }
    if txt_eq(i, "f32") == 1 { return 8 }
    if txt_eq(i, "f64") == 1 { return 9 }
    if txt_eq(i, "char") == 1 { return 10 }
    if txt_eq(i, "string") == 1 { return 11 }
    if txt_eq(i, "void") == 1 { return 12 }
    if txt_eq(i, "bool") == 1 { return 13 }
    if txt_eq(i, "fx32") == 1 { return 3 }
    if txt_eq(i, "fx64") == 1 { return 4 }
    /* 别名 */
    if txt_eq(i, "Byte") == 1 { return 5 }
    id i32 = agg_find(i)
    if id >= 0 { return 20 + id }
    return 0
}

func ctype(code i32) {
    if code == 1 { eo("int8_t") return }
    if code == 2 { eo("int16_t") return }
    if code == 3 { eo("int32_t") return }
    if code == 4 { eo("int64_t") return }
    if code == 5 { eo("uint8_t") return }
    if code == 6 { eo("uint16_t") return }
    if code == 7 { eo("uint32_t") return }
    if code == 8 { eo("float") return }
    if code == 9 { eo("double") return }
    if code == 10 { eo("char") return }
    if code == 11 { eo("char*") return }
    if code == 12 { eo("void*") return }
    if code == 13 { eo("int64_t") return }
    if code >= 20 {
        a void = gtn
        etk(a.(i32[128])[code - 20])
        return
    }
    eo("int64_t")
}

func is_float(code i32) i32 {
    if code == 8 { return 1 }
    if code == 9 { return 1 }
    return 0
}

func mem_add(agg i32, idx i32, nt i32, c i32, arr i32, ds i32, de i32) {
    if gmc >= 500 { return }
    a void = gmagg
    b void = gmidx
    n void = gmname
    cc void = gmcode
    ar void = gmarray
    d1 void = gmdef
    d2 void = gmdef2
    a.(i32[512])[gmc] = agg
    b.(i32[512])[gmc] = idx
    n.(i32[512])[gmc] = nt
    cc.(i32[512])[gmc] = c
    ar.(i32[512])[gmc] = arr
    d1.(i32[512])[gmc] = ds
    d2.(i32[512])[gmc] = de
    gmc = gmc + 1
}

/* 成员尺寸/对齐：数组标记的成员按指针（char[]）或 8 字节槽处理 */
func mem_size(slot i32) i32 {
    ar void = gmarray
    cc void = gmcode
    c i32 = cc.(i32[512])[slot]
    if ar.(i32[512])[slot] == 1 {
        if c == 10 { return 8 }
        if c == 11 { return 8 }
        return 8
    }
    return size_of_code(c)
}

func mem_align(slot i32) i32 {
    ar void = gmarray
    cc void = gmcode
    c i32 = cc.(i32[512])[slot]
    if ar.(i32[512])[slot] == 1 {
        if c == 10 { return 8 }
        return align_of(c)
    }
    return align_of(c)
}

func mem_set_bit(slot i32, w i32) {
    a void = gmbit
    if slot >= 0 { if slot < 512 { a.(i32[512])[slot] = w } }
}

func mem_bit(slot i32) i32 {
    a void = gmbit
    if slot < 0 { return 0 }
    return a.(i32[512])[slot]
}

func mem_find(agg i32, nt i32) i32 {
    a void = gmagg
    n void = gmname
    k i32 = 0
    while k < gmc {
        if a.(i32[512])[k] == agg {
            if tok_eq(n.(i32[512])[k], nt) == 1 { return k }
        }
        k = k + 1
    }
    return -1
}

/* ================= 编译期（cooking） ================= */

var gctn i32
var gctname i64
var gct i64
var gcp i32
var gcls i32
var gcle i32
var genvn i32
var gpenv i64

func ct_find(nt i32) i32 {
    a void = gctname
    k i32 = 0
    while k < gctn {
        if tok_eq(a.(i32[128])[k], nt) == 1 { return k }
        k = k - 0 + 1
    }
    return -1
}

func ct_get(i i32, f i32) i32 {
    a void = gct
    return a.(i32[1024])[i * 8 + f]
}

func ct_put(i i32, f i32, v i32) {
    a void = gct
    a.(i32[1024])[i * 8 + f] = v
}

func ct_add_const(nt i32, v i32) {
    a void = gctname
    if gctn >= 128 { return }
    a.(i32[128])[gctn] = nt
    ct_put(gctn, 0, v)
    ct_put(gctn, 1, 0)
    gctn = gctn + 1
}

func ct_add_macro(nt i32, ar i32, p1 i32, p2 i32, p3 i32, bs i32, be i32) {
    a void = gctname
    if gctn >= 128 { return }
    a.(i32[128])[gctn] = nt
    ct_put(gctn, 0, 0)
    ct_put(gctn, 1, ar)
    ct_put(gctn, 2, p1)
    ct_put(gctn, 3, p2)
    ct_put(gctn, 4, p3)
    ct_put(gctn, 5, bs)
    ct_put(gctn, 6, be)
    gctn = gctn + 1
}

func env_find(nt i32) i32 {
    a void = gpenv
    k i32 = genvn - 1
    while k >= 0 {
        if tok_eq(a.(i32[16])[k * 2], nt) == 1 { return k }
        k = k - 1
    }
    return -1
}

func env_name(k i32) i32 {
    a void = gpenv
    return a.(i32[16])[k * 2]
}

func env_val(k i32) i32 {
    a void = gpenv
    return a.(i32[16])[k * 2 + 1]
}

func env_set(k i32, nm i32, v i32) {
    a void = gpenv
    a.(i32[16])[k * 2] = nm
    a.(i32[16])[k * 2 + 1] = v
}

/* 数字 token → 值（十进制 / 0x） */
func tok_num(i i32) i32 {
    n i32 = tk_ln(i)
    st i32 = tk_st(i)
    v i32 = 0
    k i32 = 0
    if n > 2 {
        if sch(st) == 48 {
            c1 i32 = sch(st + 1)
            if c1 == 120 {
                k = 2
                while k < n {
                    d i32 = sch(st + k)
                    dv i32 = 0
                    if d >= 48 { if d <= 57 { dv = d - 48 } }
                    if d >= 97 { if d <= 102 { dv = d - 87 } }
                    if d >= 65 { if d <= 70 { dv = d - 55 } }
                    v = v * 16 + dv
                    k = k + 1
                }
                return v
            }
        }
    }
    while k < n {
        c i32 = sch(st + k)
        if c < 48 { return v }
        if c > 57 { return v }
        v = v * 10 + (c - 48)
        k = k + 1
    }
    return v
}

func ct_peek() i32 {
    if gcp >= gcle { return 8 }
    return tk_kind(gcp)
}

func ct_is(s void) i32 {
    if gcp >= gcle { return 0 }
    if tk_kind(gcp) != 6 { return 0 }
    return txt_eq(gcp, s)
}

func ct_num(i i32) i32 {
    if i < 0 { return 0 - i }
    return i
}

func ct_expr() i32 {
    return ct_or()
}

func ct_or() i32 {
    v i32 = ct_and()
    while ct_is("||") == 1 {
        gcp = gcp + 1
        w i32 = ct_and()
        if v != 0 { v = 1 } else { v = w }
    }
    return v
}

func ct_and() i32 {
    v i32 = ct_eq()
    while ct_is("&&") == 1 {
        gcp = gcp + 1
        w i32 = ct_eq()
        if v == 0 { v = 0 } else { v = w }
    }
    return v
}

func ct_eq() i32 {
    v i32 = ct_rel()
    while 1 == 1 {
        if ct_is("==") == 1 {
            gcp = gcp + 1
            w i32 = ct_rel()
            if v == w { v = 1 } else { v = 0 }
        } else if ct_is("!=") == 1 {
            gcp = gcp + 1
            w i32 = ct_rel()
            if v != w { v = 1 } else { v = 0 }
        } else {
            return v
        }
    }
    return v
}

func ct_rel() i32 {
    v i32 = ct_add()
    while 1 == 1 {
        if ct_is("<") == 1 {
            gcp = gcp + 1
            w i32 = ct_add()
            if v < w { v = 1 } else { v = 0 }
        } else if ct_is(">") == 1 {
            gcp = gcp + 1
            w i32 = ct_add()
            if v > w { v = 1 } else { v = 0 }
        } else if ct_is("<=") == 1 {
            gcp = gcp + 1
            w i32 = ct_add()
            if v <= w { v = 1 } else { v = 0 }
        } else if ct_is(">=") == 1 {
            gcp = gcp + 1
            w i32 = ct_add()
            if v >= w { v = 1 } else { v = 0 }
        } else {
            return v
        }
    }
    return v
}

func ct_add() i32 {
    v i32 = ct_mul()
    while 1 == 1 {
        if ct_is("+") == 1 {
            gcp = gcp + 1
            v = v + ct_mul()
        } else if ct_is("-") == 1 {
            gcp = gcp + 1
            v = v - ct_mul()
        } else {
            return v
        }
    }
    return v
}

func ct_mul() i32 {
    v i32 = ct_unary()
    while 1 == 1 {
        if ct_is("*") == 1 {
            gcp = gcp + 1
            v = v * ct_unary()
        } else if ct_is("/") == 1 {
            gcp = gcp + 1
            d i32 = ct_unary()
            if d != 0 { v = v / d }
        } else if ct_is("%") == 1 {
            gcp = gcp + 1
            d2 i32 = ct_unary()
            if d2 != 0 { v = v % d2 }
        } else {
            return v
        }
    }
    return v
}

func ct_unary() i32 {
    if ct_is("-") == 1 {
        gcp = gcp + 1
        return 0 - ct_unary()
    }
    if ct_is("!") == 1 {
        gcp = gcp + 1
        v i32 = ct_unary()
        if v == 0 { return 1 }
        return 0
    }
    if ct_is("+") == 1 {
        gcp = gcp + 1
        return ct_unary()
    }
    return ct_primary()
}

func ct_primary() i32 {
    if gcp >= gcle { return 0 }
    k i32 = tk_kind(gcp)
    if k == 2 {
        v i32 = tok_num(gcp)
        gcp = gcp + 1
        return v
    }
    if k == 6 {
        if ct_is("(") == 1 {
            gcp = gcp + 1
            v2 i32 = ct_expr()
            if ct_is(")") == 1 { gcp = gcp + 1 }
            return v2
        }
        gcp = gcp + 1
        return 0
    }
    if k == 1 {
        if txt_eq(gcp, "true") == 1 { gcp = gcp + 1 return 1 }
        if txt_eq(gcp, "false") == 1 { gcp = gcp + 1 return 0 }
        if txt_eq(gcp, "sizeof") == 1 {
            gcp = gcp + 1
            if ct_is("(") == 1 { gcp = gcp + 1 }
            c i32 = 0
            if gcp < gcle { c = code_of(gcp) }
            if c == 0 { c = 4 }
            gcp = gcp + 1
            while gcp < gcle {
                if ct_is("]") == 1 { gcp = gcp + 1 }
                else { if ct_is("[") == 1 { gcp = gcp + 1 } else { gcp = gcp + 1 } }
            }
            if c >= 20 { return agg_mcount(c - 20) * 8 }
            return size_of_code(c)
        }
        /* 形参 or 编译期常量 or 宏调用 */
        e1 i32 = env_find(gcp)
        if e1 >= 0 {
            v3 i32 = env_val(e1)
            gcp = gcp + 1
            return v3
        }
        mi i32 = ct_find(gcp)
        if mi >= 0 {
            nt i32 = gcp
            gcp = gcp + 1
            if ct_is("(") == 1 {
                return ct_call(mi)
            }
            return ct_get(mi, 0)
        }
        gcp = gcp + 1
        return 0
    }
    gcp = gcp + 1
    return 0
}

/* 宏式编译期函数：求实参 → 绑定形参 → 求值函数体 */
func ct_call(mi i32) i32 {
    gcp = gcp + 1
    av i32 = 0
    a1 i32 = 0
    a2 i32 = 0
    a3 i32 = 0
    if ct_is(")") == 0 {
        a1 = ct_expr()
        av = 1
        if ct_is(",") == 1 {
            gcp = gcp + 1
            a2 = ct_expr()
            av = 2
            if ct_is(",") == 1 {
                gcp = gcp + 1
                a3 = ct_expr()
                av = 3
            }
        }
    }
    if ct_is(")") == 1 { gcp = gcp + 1 }
    save_n i32 = genvn
    save_cp i32 = gcp
    save_ls i32 = gcls
    save_le i32 = gcle
    if a1 != 0 { env_set(genvn, ct_get(mi, 2), a1) genvn = genvn + 1 }
    if av >= 2 { env_set(genvn, ct_get(mi, 3), a2) genvn = genvn + 1 }
    if av >= 3 { env_set(genvn, ct_get(mi, 4), a3) genvn = genvn + 1 }
    gcp = ct_get(mi, 5)
    gcls = ct_get(mi, 5)
    gcle = ct_get(mi, 6)
    v i32 = ct_expr()
    genvn = save_n
    gcp = save_cp
    gcls = save_ls
    gcle = save_le
    return v
}

func ct_eval(st i32, en i32) i32 {
    save i32 = gcp
    sl i32 = gcls
    se i32 = gcle
    gcp = st
    gcls = st
    gcle = en
    v i32 = ct_expr()
    gcp = save
    gcls = sl
    gcle = se
    return v
}

/* cooking { ... }：const 变量 / const 宏 / static_assert */
func cooking_block() {
    adv()
    need_p("{")
    skip_nl()
    while ck() != 8 {
        if is_p("}") == 1 { adv() return }
        skip_nl()
        if is_kw("const") == 1 {
            adv()
            skip_nl()
            nt i32 = gi
            adv()
            if is_p("(") == 1 {
                /* const NAME(p1,p2) = expr */
                adv()
                p1 i32 = -1
                p2 i32 = -1
                p3 i32 = -1
                ar i32 = 0
                while is_p(")") == 0 {
                    if ck() == 1 {
                        if ar == 0 { p1 = gi }
                        if ar == 1 { p2 = gi }
                        if ar == 2 { p3 = gi }
                        ar = ar + 1
                    }
                    adv()
                    if is_p(",") == 1 { adv() }
                }
                adv()
                if is_p("=") == 1 { adv() }
                bs i32 = gi
                while ck() != 8 {
                    if tk_kind(gi) == 7 { break }
                    if is_p("}") == 1 { break }
                    adv()
                }
                ct_add_macro(nt, ar, p1, p2, p3, bs, gi)
            } else {
                /* 可选类型名 */
                if code_of(gi) > 0 { adv() }
                if is_p("=") == 1 { adv() }
                skip_nl()
                bs2 i32 = gi
                while ck() != 8 {
                    if tk_kind(gi) == 7 { break }
                    if is_p("}") == 1 { break }
                    adv()
                }
                v i32 = ct_eval(bs2, gi)
                ct_add_const(nt, v)
            }
        } else if is_kw("static_assert") == 1 {
            adv()
            need_p("(")
            skip_nl()
            bs3 i32 = gi
            depth i32 = 0
            while ck() != 8 {
                if is_p("(") == 1 { depth = depth + 1 }
                if is_p(")") == 1 {
                    if depth == 0 { break }
                    depth = depth - 1
                }
                if is_p(",") == 1 {
                    if depth == 0 { break }
                }
                adv()
            }
            v2 i32 = ct_eval(bs3, gi)
            if v2 == 0 { gerr = gerr + 1 }
            /* 跳过消息与右括号 */
            depth = 0
            while ck() != 8 {
                if is_p("(") == 1 { depth = depth + 1 }
                if is_p(")") == 1 {
                    depth = depth - 1
                    adv()
                    if depth < 0 { break }
                    continue
                }
                adv()
            }
        } else {
            if is_kw("var") == 1 { emsg("unsupported cooking item 'var'") }
            else if ck() == 1 { emsg("unsupported cooking item") }
            while ck() != 8 {
                if tk_kind(gi) == 7 { break }
                if is_p("}") == 1 { break }
                adv()
            }
        }
        skip_nl()
    }
}

/* ================= 表达式 ================= *//* ================= 表达式 ================= */

func prec_of(i i32) i32 {
    if tk_kind(i) != 6 { return 0 }
    if txt_eq(i, "*") == 1 { return 11 }
    if txt_eq(i, "/") == 1 { return 11 }
    if txt_eq(i, "%") == 1 { return 11 }
    if txt_eq(i, "+") == 1 { return 10 }
    if txt_eq(i, "-") == 1 { return 10 }
    if txt_eq(i, "<<") == 1 { return 9 }
    if txt_eq(i, ">>") == 1 { return 9 }
    if txt_eq(i, "<") == 1 { return 8 }
    if txt_eq(i, ">") == 1 { return 8 }
    if txt_eq(i, "<=") == 1 { return 8 }
    if txt_eq(i, ">=") == 1 { return 8 }
    if txt_eq(i, "==") == 1 { return 7 }
    if txt_eq(i, "!=") == 1 { return 7 }
    if txt_eq(i, "&") == 1 { return 6 }
    if txt_eq(i, "^") == 1 { return 5 }
    if txt_eq(i, "|") == 1 { return 4 }
    if txt_eq(i, "&&") == 1 { return 3 }
    if txt_eq(i, "||") == 1 { return 2 }
    return 0
}

func expr_bin(minp i32) {
    expr_unary()
    while 1 == 1 {
        p i32 = prec_of(gi)
        if p < minp { return }
        if p == 0 { return }
        tx i32 = gi
        adv()
        espace()
        etk(tx)
        espace()
        expr_bin(p + 1)
    }
}

/* 一元：+ - ! ~ & */
func expr_unary() {
    if is_p("-") == 1 {
        ec(45)
        adv()
        expr_unary()
        return
    }
    if is_p("+") == 1 {
        adv()
        expr_unary()
        return
    }
    if is_p("!") == 1 {
        ec(33)
        adv()
        expr_unary()
        return
    }
    if is_p("~") == 1 {
        ec(126)
        adv()
        expr_unary()
        return
    }
    if is_p("&") == 1 {
        ec(38)
        adv()
        expr_unary()
        return
    }
    if is_p("++") == 1 {
        eo("++")
        adv()
        expr_unary()
        return
    }
    if is_p("--") == 1 {
        eo("--")
        adv()
        expr_unary()
        return
    }
    if is_p("*") == 1 {
        /* 规范里一元 * 已移除；保守起见按解引用处理 */
        ec(42)
        adv()
        expr_unary()
        return
    }
    expr_postfix()
}

/* 后缀链：调用 / 下标 / 切片 / 成员 / .() / .(T) / -> */
func expr_postfix() {
    p0 i32 = goutn
    t0 i32 = gi
    expr_primary()
    while 1 == 1 {
        if is_p("(") == 1 {
            ec(40)
            adv()
            skip_nl()
            if is_p(")") == 0 {
                expr_assign()
                while eat_p(",") == 1 {
                    ec(44)
                    espace()
                    skip_nl()
                    expr_assign()
                }
            }
            need_p(")")
            ec(41)
            continue
        }
        if is_p("[") == 1 {
            if gslm == 1 {
                /* 捕获：只记 token 位置，不产出文本 */
                adv()
                skip_nl()
                if is_p("]") == 1 {
                    adv()
                    gslls = -1
                    gsafter = gi
                    return
                }
                if is_p("..") == 1 {
                    adv()
                    if is_p("]") == 0 { expr_assign() }
                    need_p("]")
                    gslls = -1
                    gsafter = gi
                    return
                }
                gslls = gi
                expr_assign()
                if is_p("..") == 1 {
                    adv()
                    if is_p("]") == 0 { expr_assign() }
                    need_p("]")
                }
                gsafter = gi
                return
            }
            if gslm == 2 {
                /* 重放模式：只出 base，停在 '[' 前 */
                return
            }
            adv()
            skip_nl()
            if is_p("]") == 1 {          /* p[] → (*p)，按指向类型读 */
                adv()
                tc3 i32 = 0
                if tk_kind(t0) == 1 {
                    si7 i32 = sym_find(t0)
                    if si7 >= 0 { tc3 = sym_pt(si7) }
                }
                expr_wrap_deref(p0, tc3)
                continue
            }
            if gi == t0 + 2 {
            if tk_kind(t0) == 1 {
                sv9 i32 = sym_find(t0)
                if sv9 >= 0 {
                    if sym_code(sv9) == 12 {
                        if 1 == 1 {
                            if sym_dims(sv9) == 0 {
                            emsg("cannot subscript the generic 'void' pointer (use '.(T)' first)")
                            }
                        }
                    }
            }
                }
            }
            ec(91)
            if is_p("..") == 1 {
                adv()
                ec(48)
                mh i32 = goutn
                if is_p("]") == 0 { expr_assign() }
                goutn = mh
                need_p("]")
                ec(93)
                expr_wrap_slice2(p0)
                continue
            }
            expr_assign()
            if is_p("..") == 1 {
                adv()
                mh2 i32 = goutn
                if is_p("]") == 0 { expr_assign() }
                goutn = mh2
                need_p("]")
                ec(93)
                expr_wrap_slice2(p0)
                continue
            }
            need_p("]")
            ec(93)
            continue
        }
        if is_p(".") == 1 {
            nxt i32 = gi + 1
            if tk_kind(nxt) == 6 {
                if txt_eq(nxt, "(") == 1 {
                    adv()
                    adv()
                    skip_nl()
                    tc i32 = 0
                    ds i32 = -1
                    de i32 = -1
                    texp i32 = 0
                    if is_p(")") == 0 {
                        texp = 1
                        tc = code_of(gi)
                        if tc == 0 { tc = 4 }
                        if tc == 12 {
                            if is_p("[") == 1 { }
                        }
                        adv()
                        if is_p("[") == 1 {
                            ds = gi
                            while is_p("[") == 1 {
                                adv()
                                if is_p("]") == 0 { adv() }
                                need_p("]")
                            }
                            de = gi
                        }
                        if is_p("]") == 1 { adv() }
                    }
                    need_p(")")
                    if tc == 12 {
                        if ds < 0 { emsg("'.()' dereference: 'void' has no size — use a scalar type") }
                    }
                    if texp == 1 {
                    if tk_kind(t0) == 1 {
                        sv11 i32 = sym_find(t0)
                        if sv11 >= 0 {
                            sc10 void = gslice
                            sz10 i32 = sc10.(i32[512])[sv11]
                            if sz10 > 0 {
                                if size_of_code(tc) > sz10 {
                                    print("错误: reads %d bytes from a %d-byte allocation\n", size_of_code(tc), sz10)
                                    gerr = gerr + 1
                                }
                            }
                        }
                    }
                    }
                    if ds >= 0 {
                        expr_wrap_deref_arr(p0, tc, ds, de)
                    } else {
                        if tc == 0 {
                            if tk_kind(t0) == 1 {
                                si2 i32 = sym_find(t0)
                                if si2 >= 0 { tc = sym_pt(si2) }
                            }
                        }
                        expr_wrap_deref(p0, tc)
                    }
                    continue
                }
            }
            if gi == t0 + 1 {
                if tk_kind(t0) == 1 {
                    sv10 i32 = sym_find(t0)
                    if sv10 >= 0 {
                        if sym_code(sv10) == 12 {
                            if sym_dims(sv10) == 0 {
                                if sym_pt(sv10) < 20 {
                                    emsg("cannot access a member of the generic 'void' pointer")
                                }
                            }
                        }
                    }
                }
            }
            ec(46)
            adv()
            etk(gi)
            adv()
            continue
        }
        if is_p("->") == 1 {
            tc2 i32 = 0
            if gi == t0 + 1 {
                if tk_kind(t0) == 1 {
                    si6 i32 = sym_find(t0)
                    if si6 >= 0 {
                        tc2 = sym_pt(si6)
                        if sym_code(si6) == 12 {
                            if sym_dims(si6) == 0 {
                                if tc2 < 20 {
                                    emsg("cannot access a member of the generic 'void' pointer")
                                }
                            }
                        }
                    }
                }
            }
            if tc2 >= 20 {
                n2 i32 = goutn - p0
                tmp2 i32 = 519000 - n2
                o2 void = gout
                k3 i32 = 0
                while k3 < n2 {
                    o2.(i8[524288])[tmp2 + k3] = o2.(i8[524288])[p0 + k3]
                    k3 = k3 + 1
                }
                goutn = p0
                eo("(((")
                ctype(tc2)
                eo("*)(")
                k3 = 0
                while k3 < n2 {
                    ec(o2.(i8[524288])[tmp2 + k3])
                    k3 = k3 + 1
                }
                eo(")))")
            }
            ec(45)
            ec(62)
            adv()
            etk(gi)
            adv()
            continue
        }
        return
    }
}

/* .(T[N])：把通用指针固定成「指向 T[N]」再解引用 */
func expr_wrap_deref_arr(p0 i32, tcode i32, ds i32, de i32) {
    n i32 = goutn - p0
    tmp i32 = 522000 - n
    o void = gout
    k i32 = 0
    while k < n {
        o.(i8[524288])[tmp + k] = o.(i8[524288])[p0 + k]
        k = k + 1
    }
    goutn = p0
    eo("(*((")
    ctype(tcode)
    eo("(*)")
    k = ds
    while k < de {
        etk(k)
        k = k + 1
    }
    eo(")(")
    k = 0
    while k < n {
        ec(o.(i8[524288])[tmp + k])
        k = k + 1
    }
    eo(")))")
}

/* 把 [p0, goutn) 这段已生成的文本搬到临时区，再整体包一层 */
func expr_wrap_deref(p0 i32, tcode i32) {
    n i32 = goutn - p0
    /* 先挪到输出尾部之外的临时缓冲：直接在原位右移不方便，改为拷贝到栈外缓冲 */
    tmp i32 = 524000 - n
    o void = gout
    k i32 = 0
    while k < n {
        o.(i8[524288])[tmp + k] = o.(i8[524288])[p0 + k]
        k = k + 1
    }
    goutn = p0
    eo("(*((")
    if tcode > 0 { ctype(tcode) } else { eo("int64_t") }
    eo("*)(")
    k = 0
    while k < n {
        ec(o.(i8[524288])[tmp + k])
        k = k + 1
    }
    eo(")))")
}

func expr_wrap_slice2(p0 i32) {
    n i32 = goutn - p0
    tmp i32 = 523000 - n
    if tmp < 0 { return }
    o void = gout
    k i32 = 0
    while k < n {
        o.(i8[524288])[tmp + k] = o.(i8[524288])[p0 + k]
        k = k + 1
    }
    goutn = p0
    eo("(&(")
    k = 0
    while k < n {
        ec(o.(i8[524288])[tmp + k])
        k = k + 1
    }
    eo("))")
}

func expr_wrap_slice(p0 i32, mode i32, dummy i32) {
    need_p("]")
    n i32 = goutn - p0
    tmp i32 = 523000 - n
    o void = gout
    k i32 = 0
    while k < n {
        o.(i8[524288])[tmp + k] = o.(i8[524288])[p0 + k]
        k = k + 1
    }
    goutn = p0
    eo("(&(")
    k = 0
    while k < n {
        ec(o.(i8[524288])[tmp + k])
        k = k + 1
    }
    eo("))")
}

func expr_primary() {
    k i32 = ck()
    if k == 2 { etk(gi) adv() return }
    if k == 3 { etk(gi) adv() return }
    if k == 4 { etk(gi) adv() return }
    if k == 5 { etk(gi) adv() return }
    if k == 6 {
        if is_p("(") == 1 {
            ec(40)
            adv()
            skip_nl()
            expr_assign()
            need_p(")")
            ec(41)
            return
        }
        if is_p("{") == 1 {
            /* 聚合初值（表达式位置） */
            ec(123)
            adv()
            skip_nl()
            if is_p("}") == 0 {
                expr_assign()
                while eat_p(",") == 1 {
                    ec(44)
                    espace()
                    skip_nl()
                    expr_assign()
                }
            }
            need_p("}")
            ec(125)
            return
        }
        eo("0")
        adv()
        return
    }
    if k == 1 {
        /* 内置函数 */
        if txt_eq(gi, "true") == 1 { eo("1") adv() return }
        if txt_eq(gi, "false") == 1 { eo("0") adv() return }
        if txt_eq(gi, "_undef") == 1 { eo("0") adv() return }
        if txt_eq(gi, "_const") == 1 { eo("1") adv() return }
        if txt_eq(gi, "_flow") == 1 { eo("2") adv() return }
        if txt_eq(gi, "_static") == 1 { eo("3") adv() return }
        if txt_eq(gi, "_var") == 1 { eo("4") adv() return }
        if txt_eq(gi, "visof") == 1 { emit_visof() return }
        if txt_eq(gi, "sizeof") == 1 { emit_sizeof("sizeof") return }
        if txt_eq(gi, "alignof") == 1 { emit_alignof() return }
        if txt_eq(gi, "typeof") == 1 { emit_sizeof("sizeof") return }
        if txt_eq(gi, "offsetof") == 1 { emit_offsetof() return }
        if txt_eq(gi, "len") == 1 { emit_len() return }
        if txt_eq(gi, "malloc") == 1 { emit_malloc() return }
        if txt_eq(gi, "print") == 1 { emit_print() return }
        if txt_eq(gi, "structof") == 1 { emit_ownerof(1) return }
        if txt_eq(gi, "holdof") == 1 { emit_ownerof(2) return }
        if txt_eq(gi, "unionof") == 1 { emit_ownerof(3) return }
        if txt_eq(gi, "bitoffsetof") == 1 { emit_bitoff() return }
        if ck() == 1 {
            si8 i32 = sym_find(gi)
            if si8 >= 0 {
                st8 void = gstate
                if st8.(i32[512])[si8] == 1 {
                    tok_cstr(gi)
                    print("错误: use of frozen pointer '%s'\n", gout)
                    gerr = gerr + 1
                    st8.(i32[512])[si8] = 0
                } else if st8.(i32[512])[si8] == 2 {
                    tok_cstr(gi)
                    print("错误: use of invalidated pointer '%s'\n", gout)
                    gerr = gerr + 1
                    st8.(i32[512])[si8] = 0
                }
            }
        }
        /* 编译期常量折叠 */
        ci i32 = ct_find(gi)
        if ci >= 0 {
            if ct_get(ci, 1) == 0 {
                enum_i(ct_get(ci, 0))
                adv()
                return
            }
        }
        /* 普通标识符 */
        etk(gi)
        adv()
        return
    }
}

/* structof/holdof/unionof(T, member, p) → 反推所属对象首地址 */
func emit_ownerof(kind i32) {
    adv()
    need_p("(")
    skip_nl()
    tc i32 = code_of(gi)
    if tc < 20 { tc = 20 }
    adv()
    need_p(",")
    skip_nl()
    mt i32 = gi
    adv()
    if mem_find(tc - 20, mt) < 0 { emsg("no member of that name in the aggregate type") }
    need_p(",")
    skip_nl()
    eo("(void*)((char*)(")
    expr_assign()
    eo(") - ")
    enum_i(mem_off_of(tc - 20, mt))
    eo(")")
    need_p(")")
}

func emit_bitoff() {
    adv()
    need_p("(")
    skip_nl()
    tc i32 = code_of(gi)
    if tc < 20 { tc = 20 }
    adv()
    need_p(",")
    skip_nl()
    mt i32 = gi
    adv()
    need_p(")")
    enum_i(bit_off_of(tc - 20, mt))
}

func emit_visof() {
    adv()
    if is_p("(") == 1 { adv() }
    v i32 = 0
    if ck() == 1 {
        si i32 = sym_find(gi)
        if si >= 0 { v = sym_vis(si) }
        adv()
    }
    if is_p(")") == 1 { adv() }
    enum_i(v)
}

func size_of_code(code i32) i32 {
    if code == 1 { return 1 }
    if code == 5 { return 1 }
    if code == 10 { return 1 }
    if code == 13 { return 1 }
    if code == 2 { return 2 }
    if code == 6 { return 2 }
    if code == 3 { return 4 }
    if code == 7 { return 4 }
    if code == 8 { return 4 }
    if code == 4 { return 8 }
    if code == 9 { return 8 }
    if code == 11 { return 8 }
    if code == 12 { return 8 }
    if code >= 20 { return agg_mcount(code - 20) * 8 }
    return 8
}

func align_up(v i32, a i32) i32 {
    if a <= 1 { return v }
    r i32 = v % a
    if r == 0 { return v }
    return v + (a - r)
}

/* 成员位偏移（bit）：按 C 布局 + 同类型位域单元打包 */
func bit_off_of(agg i32, nt i32) i32 {
    a void = gmagg
    nm void = gmname
    cc void = gmcode
    byte i32 = 0
    unit i32 = 0
    bitin i32 = 0
    k i32 = 0
    while k < gmc {
        if a.(i32[512])[k] == agg {
            c i32 = cc.(i32[512])[k]
            sz i32 = mem_size(k)
            al i32 = mem_align(k)
            bw i32 = mem_bit(k)
            if bw > 0 {
                if unit == 0 {
                    byte = align_up(byte, al)
                    unit = sz
                    bitin = 0
                }
                if bitin + bw > unit * 8 {
                    byte = byte + unit
                    byte = align_up(byte, al)
                    unit = sz
                    bitin = 0
                }
                if tok_eq(nm.(i32[512])[k], nt) == 1 { return byte * 8 + bitin }
                bitin = bitin + bw
                if bitin >= unit * 8 {
                    byte = byte + unit
                    unit = 0
                    bitin = 0
                }
            } else {
                unit = 0
                bitin = 0
                byte = align_up(byte, al)
                if tok_eq(nm.(i32[512])[k], nt) == 1 { return byte * 8 }
                byte = byte + sz
            }
        }
        k = k + 1
    }
    return 0
}

func mem_off_of(agg i32, nt i32) i32 {
    a void = gmagg
    nm void = gmname
    cc void = gmcode
    byte i32 = 0
    k i32 = 0
    while k < gmc {
        if a.(i32[512])[k] == agg {
            c i32 = cc.(i32[512])[k]
            sz i32 = mem_size(k)
            al i32 = mem_align(k)
            byte = align_up(byte, al)
            if tok_eq(nm.(i32[512])[k], nt) == 1 { return byte }
            byte = byte + sz
        }
        k = k + 1
    }
    return 0
}

func agg_mcount(agg i32) i32 {
    a void = gmagg
    n i32 = 0
    k i32 = 0
    while k < gmc {
        if a.(i32[512])[k] == agg { n = n + 1 }
        k = k + 1
    }
    return n
}

func align_of(code i32) i32 {
    if code == 1 { return 1 }
    if code == 5 { return 1 }
    if code == 10 { return 1 }
    if code == 13 { return 1 }
    if code == 2 { return 2 }
    if code == 6 { return 2 }
    if code == 3 { return 4 }
    if code == 7 { return 4 }
    if code == 8 { return 4 }
    if code == 4 { return 8 }
    if code == 9 { return 8 }
    if code == 11 { return 8 }
    if code == 12 { return 8 }
    if code >= 20 {
        a void = gmagg
        cc void = gmcode
        k i32 = 0
        mx i32 = 1
        while k < gmc {
            if a.(i32[512])[k] == code - 20 {
                av i32 = align_of(cc.(i32[512])[k])
                if av > mx { mx = av }
            }
            k = k + 1
        }
        return mx
    }
    return 8
}

func emit_alignof() {
    adv()
    need_p("(")
    skip_nl()
    c i32 = code_of(gi)
    if c > 0 {
        adv()
        while is_p("[") == 1 { adv() if is_p("]") == 0 { adv() } need_p("]") }
    } else {
        c = 12
    }
    need_p(")")
    enum_i(align_of(c))
}

func emit_sizeof(which i32) {
    adv()
    need_p("(")
    skip_nl()
    c i32 = code_of(gi)
    if c >= 20 {
        /* ncc 口径：聚合 sizeof = 顶层成员数 × 8（槽模型） */
        adv()
        while is_p("[") == 1 { adv() if is_p("]") == 0 { adv() } need_p("]") }
        enum_i(agg_mcount(c - 20) * 8)
        need_p(")")
        return
    }
    if c > 0 {
        eo("sizeof(")
        ctype(c)
        adv()
        while is_p("[") == 1 {
            eo("[")
            adv()
            if is_p("]") == 1 { adv() eo("8") }
            else {
                if ck() == 2 { etk(gi) adv() } else { eo("8") }
                if is_p("..") == 1 { adv() }
                if is_p("...") == 1 { adv() }
                need_p("]")
            }
            eo("]")
        }
        eo(")")
    } else {
        eo("sizeof(int64_t)")
    }
    need_p(")")
}

func emit_offsetof() {
    adv()
    need_p("(")
    skip_nl()
    c i32 = code_of(gi)
    eo("offsetof(")
    if c > 0 { ctype(c) } else { eo("int64_t") }
    adv()
    eo(",")
    espace()
    if is_p(",") == 1 { adv() }
    if ck() == 1 { etk(gi) adv() }
    eo(")")
    while is_p(",") == 1 {
        adv()
        if ck() == 1 { adv() }
    }
    need_p(")")
}

func emit_len() {
    adv()
    need_p("(")
    skip_nl()
    if ck() == 1 {
        si i32 = sym_find(gi)
        if si >= 0 {
            sl void = gslice
            if sl.(i32[512])[si] > 0 {
                enum_i(sl.(i32[512])[si] - 1)
                adv()
                need_p(")")
                return
            }
            d i32 = sym_dims(si)
            c i32 = sym_code(si)
            if d >= 100 {
                eo("(int64_t)strlen(")
                etk(gi)
                eo(")")
                adv()
                need_p(")")
                return
            }
            if d > 0 {
                eo("(int64_t)(sizeof(")
                etk(gi)
                eo(")/sizeof(")
                etk(gi)
                k2 i32 = 0
                while k2 < d {
                    eo("[0]")
                    k2 = k2 + 1
                }
                eo("))")
                adv()
                need_p(")")
                return
            }
            if c == 11 { eo("(int64_t)strlen(") etk(gi) eo(")") adv() need_p(")") return }
            if c == 10 { eo("(int64_t)strlen(") etk(gi) eo(")") adv() need_p(")") return }
        }
    }
    if ck() == 4 {
        /* 字面量长度 */
        n i32 = tk_ln(gi) - 2
        enum_i(n)
        adv()
        need_p(")")
        return
    }
    tok_cstr(gi)
    print("错误: len: logical length of '%s' is not statically known\n", gout)
    gerr = gerr + 1
    while is_p(")") == 0 {
        if ck() == 8 { break }
        adv()
    }
    need_p(")")
}

func emit_malloc() {
    adv()
    need_p("(")
    skip_nl()
    c i32 = code_of(gi)
    eo("malloc(")
    cnt i32 = 0
    if c > 0 {
        adv()
        while is_p("[") == 1 {
            adv()
            if is_p("]") == 0 {
                if cnt > 0 { espace() ec(42) espace() }
                ec(40)
                etk(gi)
                ec(41)
                cnt = cnt + 1
                adv()
            }
            need_p("]")
        }
        if cnt > 0 { espace() ec(42) espace() }
        eo("sizeof(")
        ctype(c)
        eo(")")
    } else {
        eo("8")
    }
    eo(")")
    need_p(")")
}

/* print：首实参是字符串字面量 → printf 直通；否则 → printf("%lld\n", (long long)e) */
func emit_print() {
    adv()
    need_p("(")
    skip_nl()
    islit i32 = 0
    if ck() == 4 { islit = 1 }
    if islit == 1 {
        eo("printf(")
        expr_assign()
        while eat_p(",") == 1 {
            eo(",")
            espace()
            expr_assign()
        }
        eo(")")
    } else {
        eo("printf(\"%lld")
        eo("\\n\", ")
        eo("(long long)(")
        expr_assign()
        while eat_p(",") == 1 {
            adv()
        }
        eo("))")
    }
    need_p(")")
}

/* 赋值层：兼容 = 与复合赋值 */
func expr_assign() {
    expr_cond()
    if ck() == 6 {
        if txt_eq(gi, "=") == 1 {
            espace() ec(61) espace()
            adv()
            skip_nl()
            expr_assign()
            return
        }
        if txt_eq(gi, "+=") == 1 { espace() eo("+=") espace() adv() expr_assign() return }
        if txt_eq(gi, "-=") == 1 { espace() eo("-=") espace() adv() expr_assign() return }
        if txt_eq(gi, "*=") == 1 { espace() eo("*=") espace() adv() expr_assign() return }
        if txt_eq(gi, "/=") == 1 { espace() eo("/=") espace() adv() expr_assign() return }
        if txt_eq(gi, "%=") == 1 { espace() eo("%=") espace() adv() expr_assign() return }
        if txt_eq(gi, "&=") == 1 { espace() eo("&=") espace() adv() expr_assign() return }
        if txt_eq(gi, "|=") == 1 { espace() eo("|=") espace() adv() expr_assign() return }
        if txt_eq(gi, "^=") == 1 { espace() eo("^=") espace() adv() expr_assign() return }
        if txt_eq(gi, "++") == 1 { eo("++") adv() return }
        if txt_eq(gi, "--") == 1 { eo("--") adv() return }
    }
}

func expr_cond() {
    expr_bin(2)
    if is_p("?") == 1 {
        espace() ec(63) espace()
        adv()
        skip_nl()
        expr_assign()
        espace() ec(58) espace()
        need_p(":")
        skip_nl()
        expr_assign()
    }
}

/* ================= 声明 ================= */

/* 在前缀（可见性）之后，判断 i 处是否是「名字 类型」声明 */
func decl_start(i i32) i32 {
    if tk_kind(i) != 1 { return 0 }
    ni i32 = i + 1
    if tk_kind(ni) == 1 {
        if code_of(ni) > 0 { return 1 }
    }
    if tk_kind(ni) == 6 {
        if txt_eq(ni, "{") == 1 { return 2 }   /* var {a=..} T */
        if txt_eq(ni, "(") == 1 {
            if code_of(ni + 1) > 0 { return 1 }  /* (T) 括号类型 */
        }
    }
    return 0
}

/* 解析类型之后的部分（数组维数），返回维数 */
func parse_dims() i32 {
    d i32 = 0
    while is_p("[") == 1 {
        adv()
        if is_p("]") == 1 {
            d = d + 1
            adv()
        } else {
            if is_p("...") == 1 { adv() }
            else if is_p("..") == 1 { adv() }
            else { etk(gi) adv() }
            if is_p("...") == 1 { adv() }
            need_p("]")
            d = d + 1
        }
    }
    return d
}

/* 输出数组维度（从当前 token 开始），同时返回维数 */
func emit_dims() i32 {
    d i32 = 0
    while is_p("[") == 1 {
        ec(91)
        adv()
        if is_p("]") == 1 {
            adv()
        } else {
            if is_p("...") == 1 { adv() }
            else if is_p("..") == 1 { adv() }
            else {
                etk(gi)
                adv()
            }
            if is_p("...") == 1 { adv() }
            need_p("]")
        }
        ec(93)
        d = d + 1
    }
    return d
}

/* 取数组维度原文（给符号表记 len 用），跳过并返回首维 token（-1） */
func skip_dims() i32 {
    d i32 = 0
    while is_p("[") == 1 {
        adv()
        if is_p("]") == 1 {
            adv()
        } else {
            if is_p("...") == 1 { adv() }
            else if is_p("..") == 1 { adv() }
            else { adv() }
            if is_p("...") == 1 { adv() }
            if is_p("..") == 1 { adv() }
            if ck() == 2 { adv() }
            need_p("]")
        }
        d = d + 1
    }
    return d
}

/* 首维是否为空（char[] 这类） */
func skip_first_dim() {
    if is_p("[") == 0 { return }
    depth i32 = 0
    while ck() != 8 {
        if is_p("[") == 1 { depth = depth + 1 }
        adv()
        if is_p("]") == 1 {
            depth = depth - 1
            adv()
            if depth <= 0 { return }
        }
    }
}

func tok_int(i i32) i32 {
    if tk_kind(i) != 2 { return -1 }
    n i32 = tk_ln(i)
    st i32 = tk_st(i)
    v i32 = 0
    k i32 = 0
    while k < n {
        c i32 = sch(st + k)
        if c < 48 { return -1 }
        if c > 57 { return -1 }
        v = v * 10 + (c - 48)
        k = k + 1
    }
    return v
}

func first_dim_empty(st i32, en i32) i32 {
    if st >= en { return 0 }
    if tk_kind(st) != 6 { return 0 }
    if txt_eq(st, "[") == 0 { return 0 }
    if st + 1 >= en { return 0 }
    if tk_kind(st + 1) == 6 {
        if txt_eq(st + 1, "]") == 1 { return 1 }
    }
    return 0
}

/* 输出规范化后的 C 维度：[] → [8]；[N..]/[..N] → [N]；char 首维为空则不输出（由调用方发 char*） */
func emit_dims_c(c i32) i32 {
    d i32 = 0
    while is_p("[") == 1 {
        adv()
        if is_p("]") == 1 {
            adv()
            if c == 10 {
                if d == 0 { d = d + 1 continue }
            }
            eo("[8]")
            d = d + 1
        } else {
            eo("[")
            if is_p("..") == 1 {
                adv()
                if ck() == 2 { etk(gi) adv() } else { eo("8") }
            } else if is_p("...") == 1 {
                adv()
                if ck() == 2 { etk(gi) adv() } else { eo("8") }
            } else {
                if ck() == 2 { etk(gi) adv() } else { eo("8") }
                if is_p("..") == 1 { adv() }
                if is_p("...") == 1 { adv() }
            }
            need_p("]")
            eo("]")
            d = d + 1
        }
    }
    return d
}

/* 局部声明：name TYPE [dims] [= init]  （已确认是声明） */
func emit_local_decl(vis i32) {
    nameTok i32 = gi
    adv()
    skip_nl()
    c i32 = 0
    /* (T) 括号类型 */
    if is_p("(") == 1 {
        adv()
        c = code_of(gi)
        adv()
        need_p(")")
    } else {
        c = code_of(gi)
        adv()
    }
    if c == 0 { c = 4 }
    /* 函数指针类型：name void(params) ret —— 走特殊路径 */
    if is_p("(") == 1 {
        emit_fnptr_decl(nameTok, c, vis)
        return
    }
    d i32 = skip_dims()
    si i32 = sym_add(nameTok, c, d, 0, vis)

    /* 类型前缀 */
    if d == 0 {
        if c == 10 {
            /* char 标量 */
            eo("char")
        } else if c == 11 {
            eo("char*")
        } else if c == 12 {
            eo("void*")
        } else {
            ctype(c)
        }
    } else {
        if c == 10 {
            if d == 1 {
                /* char[] 无长度 → 视初值决定数组或指针 */
                if is_p("=") == 1 {
                    adv()
                    skip_nl()
                    if ck() == 4 {
                        eo("char ")
                        etk(nameTok)
                        ec(91)
                        ec(93)
                        espace()
                        ec(61)
                        espace()
                        etk(gi)
                        adv()
                        return
                    }
                    eo("char* ")
                    etk(nameTok)
                    espace()
                    ec(61)
                    espace()
                    expr_assign()
                    return
                }
                eo("char* ")
                etk(nameTok)
                return
            }
        }
        ctype(c)
        espace()
    }
    etk(nameTok)

    /* 重新输出维度（原文），并记第一维给 len() */
    /* 注意：skip_dims 已越过维度，这里按 token 回放不容易；改用「先记位置再输出」策略：
       由 emit_local_decl2 处理，见下。 */
    need_p("")
}

/* 上面的简单版不够：重写为「先记维度位置 → 输出名字 → 回放维度」 */
func emit_fnptr_decl(nameTok i32, retc i32, vis i32) {
    /* 当前 token 是 '('：收集参数类型 → 读返回类型 → 组装 RET (*name)(types) */
    mark i32 = goutn
    depth i32 = 1
    adv()
    first i32 = 1
    while depth > 0 {
        if ck() == 8 { break }
        if is_p("(") == 1 { depth = depth + 1 adv() continue }
        if is_p(")") == 1 {
            depth = depth - 1
            adv()
            continue
        }
        skip_nl()
        if depth == 1 {
            /* 参数：函数指针类型里只有类型；也容忍 name type 写法 */
            if is_kw("const") == 1 { adv() }
            else if is_kw("flow") == 1 { adv() }
            else if is_kw("static") == 1 { adv() }
            else if is_kw("var") == 1 { adv() }
            if ck() == 1 {
                pc i32 = code_of(gi)
                if pc > 0 {
                    adv()
                } else {
                    adv()
                    skip_nl()
                    pc = code_of(gi)
                    if pc == 0 { pc = 4 }
                    adv()
                }
                pd i32 = skip_dims()
                if first == 0 { eo(", ") }
                first = 0
                if pc == 12 { eo("void* ") }
                else if pc == 11 { eo("char* ") }
                else if pc == 10 {
                    if pd > 0 { eo("char* ") } else { eo("char ") }
                } else {
                    ctype(pc)
                    espace()
                }
            } else {
                adv()
            }
            if is_p(",") == 1 { adv() }
            continue
        }
        adv()
    }
    nargs i32 = goutn - mark
    tmp i32 = 515000
    o void = gout
    k i32 = 0
    while k < nargs {
        o.(i8[524288])[tmp + k] = o.(i8[524288])[mark + k]
        k = k + 1
    }
    goutn = mark
    /* 返回类型 */
    skip_nl()
    rv i32 = 0
    if is_kw("const") == 1 { rv = 1 adv() }
    else if is_kw("flow") == 1 { rv = 2 adv() }
    else if is_kw("static") == 1 { rv = 3 adv() }
    else if is_kw("var") == 1 { rv = 4 adv() }
    rc i32 = code_of(gi)
    if rc == 0 { rc = 12 }
    if rc > 0 { adv() }
    if rc == 12 {
        if rv > 0 { eo("void* ") } else { eo("void ") }
    } else if rc == 11 { eo("char* ") }
    else if rc == 10 { eo("char ") }
    else {
        ctype(rc)
        espace()
    }
    eo("(*")
    etk(nameTok)
    eo(")(")
    k = 0
    while k < nargs {
        ec(o.(i8[524288])[tmp + k])
        k = k + 1
    }
    eo(")")
    sym_add(nameTok, 12, 0, rc, vis)
    if is_p("=") == 1 {
        espace() ec(61) espace()
        adv()
        skip_nl()
        expr_assign()
    }
    eo(";")
}

/* ================= 语句 ================= */

func block() {
    fr i32[64]
    fn2 i32 = 0
    need_p("{")
    eo("{ ")
    skip_nl()
    while ck() != 8 {
        if is_p("}") == 1 {
            adv()
            break
        }
        stmt()
        skip_nl()
        if glastfrz >= 0 {
            if fn2 < 64 {
                fr[fn2] = glastfrz
                fn2 = fn2 + 1
            }
            glastfrz = 0 - 1
        }
    }
    ks i32 = 0
    while ks < fn2 {
        stf void = gstate
        stf.(i32[512])[fr[ks]] = 0
        ks = ks + 1
    }
    eo("}")
}

func stmt() {
    skip_nl()
    if ck() == 8 { return }
    if is_p("}") == 1 { return }
    if is_p(";") == 1 { adv() return }
    if is_p("{") == 1 { block() return }
    prev_is i32 = glastis
    glastis = 0

    vis i32 = 4
    hasv i32 = 0
    if is_kw("const") == 1 { vis = 1 adv() hasv = 1 }
    else if is_kw("flow") == 1 { vis = 2 adv() hasv = 1 }
    else if is_kw("static") == 1 { vis = 3 adv() hasv = 1 }
    else if is_kw("var") == 1 { vis = 4 adv() hasv = 1 }

    if is_kw("if") == 1 { emit_if() return }
    if is_kw("while") == 1 { emit_while() return }
    if is_kw("do") == 1 { emit_do() return }
    if is_kw("for") == 1 { emit_for() return }
    if is_kw("switch") == 1 { emit_switch() return }
    if is_kw("break") == 1 { eo("break;") adv() return }
    if is_kw("continue") == 1 { eo("continue;") adv() return }
    if is_kw("return") == 1 { emit_return() return }
    if is_p("++") == 1 {
        eo("++")
        adv()
        expr_unary()
        eo(";")
        return
    }
    if is_p("--") == 1 {
        eo("--")
        adv()
        expr_unary()
        eo(";")
        return
    }
    if is_kw("goto") == 1 {
        eo("goto ")
        adv()
        etk(gi)
        adv()
        eo(";")
        return
    }
    if is_kw("cooking") == 1 {
        cooking_block()
        return
    }
    if is_kw("static_assert") == 1 {
        adv()
        skip_parens()
        return
    }
    if is_kw("is") == 1 { emit_is(prev_is) glastis = 1 return }
    if hasv == 1 {
        if is_p("{") == 1 {
            emit_multi_decl(vis)
            return
        }
    }
    if ck() == 1 {
        if is_kw_at(gi + 1, "struct") == 1 {
            if gskipdefs == 1 { mk8 i32 = goutn emit_type_def(1, 0) goutn = mk8 return }
            emit_type_def(1, 0)
            return
        }
        if is_kw_at(gi + 1, "union") == 1 {
            if gskipdefs == 1 { mk8b i32 = goutn emit_type_def(2, 0) goutn = mk8b return }
            emit_type_def(2, 0)
            return
        }
        if is_kw_at(gi + 1, "enum") == 1 {
            if gskipdefs == 1 { mk8c i32 = goutn emit_type_def(3, 0) goutn = mk8c return }
            emit_type_def(3, 0)
            return
        }
    }

    /* 标签 name: */
    if ck() == 1 {
        if tk_kind(gi + 1) == 6 {
            if txt_eq(gi + 1, ":") == 1 {
                etk(gi)
                eo(":")
                adv()
                adv()
                return
            }
        }
    }

    if ck() == 1 {
        if sym_find(gi) >= 0 {
            c0 i32 = sym_find(gi)
            if sym_vis(c0) == 1 {
                if stmt_is_store(gi) == 1 {
                    tok_cstr(gi)
                    if is_rebind(gi) == 1 {
                        print("错误: cannot assign to the const '%s'\n", gout)
                    } else {
                        print("错误: cannot modify the const '%s'\n", gout)
                    }
                    gerr = gerr + 1
                    skip_line()
                    return
                }
            }
        }
    }
    if ck() == 1 {
        if tk_kind(gi + 1) == 6 {
            if txt_eq(gi + 1, "(") == 1 {
                if tk_kind(gi + 2) == 1 {
                    if tk_kind(gi + 3) == 6 {
                        if txt_eq(gi + 3, ")") == 1 {
                            pv9 i32 = fn_param_vis(gi, 0)
                            av9 i32 = 0
                            sv13 i32 = sym_find(gi + 2)
                            if sv13 >= 0 { av9 = sym_vis(sv13) }
                            if pv9 > 0 {
                                if av9 == 1 {
                                if vis_ok(av9, pv9) == 0 {
                                    tok_cstr(gi + 2)
                                    print("错误: argument %s (visibility %s): target lifetime shorter than source\n", gout, vis_name(av9))
                                    gerr = gerr + 1
                                }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    if is_p("?=") == 1 { emsg("语法记号 '?=' 已移除，请用 '='") adv() skip_nl() return }
    if is_p("?.") == 1 { emsg("语法记号 '?.' 已移除，请用 '.()'") adv() return }

    /* 声明 or 表达式语句 */
    ds i32 = decl_start(gi)
    if ds == 1 { emit_decl(vis) return }
    if ds == 2 { emit_multi_decl(vis) return }
    if is_slice_assign() == 1 {
        emit_slice_assign()
        return
    }

    /* 隐式声明：p = &x / sl = arr[a..b] / talk = obj.member */
    if ck() == 1 {
        if sym_find(gi) < 0 {
            if tk_kind(gi + 1) == 6 {
                if txt_eq(gi + 1, "=") == 1 {
                    nt i32 = gi
                    nx i32 = gi + 2
                    if tk_kind(nx) == 4 {
                        eo("char* ")
                        etk(nt)
                        si5 i32 = sym_add(nt, 10, 100, 0, vis)
                        espace() ec(61) espace()
                        if vis != 1 { eo("__nihao_strdup(") }
                        etk(nx)
                        if vis != 1 { eo(")") }
                        eo(";")
                        gi = nx + 1
                        return
                    }
                    if tk_kind(nx) == 6 {
                        if txt_eq(nx, "&") == 1 {
                            if tk_kind(nx + 1) == 1 {
                                bs i32 = sym_find(nx + 1)
                                if bs >= 0 {
                                    sym_add(nt, 12, 0, sym_code(bs), vis)
                                    ctype(sym_code(bs))
                                    eo("*")
                                    etk(nt)
                                    espace()
                                    ec(61)
                                    espace()
                                    eo("&")
                                    etk(nx + 1)
                                    eo(";")
                                    gi = nx + 2
                                    return
                                }
                            }
                        }
                    }
                    if tk_kind(nx) == 1 {
                        if tk_kind(nx + 1) == 6 {
                            if txt_eq(nx + 1, "(") == 1 {
                                eo("int64_t ")
                                etk(nt)
                                sym_add(nt, 4, 0, 0, vis)
                                espace()
                                ec(61)
                                espace()
                                gi = nx
                                expr_assign()
                                eo(";")
                                return
                            }
                        }
                        si3 i32 = sym_find(nx)
                        if si3 >= 0 {
                            if sym_pt(si3) > 0 {
                                if tk_kind(nx + 1) == 6 {
                                    ptc i32 = sym_pt(si3)
                                    if ptc == 12 {
                                        eo("void* ")
                                    } else {
                                        ctype(ptc)
                                        eo("*")
                                    }
                                    etk(nt)
                                    sym_add(nt, 12, 0, ptc, vis)
                                    espace() ec(61) espace()
                                    gi = nx
                                    expr_assign()
                                    eo(";")
                                    return
                                }
                            }
                            /* 切片：sl = arr[a..b] → 元素类型指针 */
                            if tk_kind(nx + 1) == 6 {
                                if txt_eq(nx + 1, "[") == 1 {
                                    ctype(sym_code(si3))
                                    eo("*")
                                    etk(nt)
                                    nsi i32 = sym_add(nt, 12, 0, sym_code(si3), vis)
                                    espace()
                                    ec(61)
                                    espace()
                                    /* 捕获 lo/hi 以记下切片长度 */
                                    mark9 i32 = goutn
                                    gi = nx
                                    gslm = 1
                                    expr_postfix()
                                    gslm = 0
                                    goutn = mark9
                                    lo i32 = 0
                                    if gslls >= 0 { lo = tok_int(gslls) }
                                    hi i32 = tok_int(gsafter - 2)
                                    if hi >= lo {
                                        if lo >= 0 {
                                            sl2 void = gslice
                                            sl2.(i32[512])[nsi] = hi - lo + 1
                                        }
                                    }
                                    gi = nx
                                    expr_assign()
                                    eo(";")
                                    return
                                }
                                /* 成员：talk = obj.member */
                                if txt_eq(nx + 1, ".") == 1 {
                                    if tk_kind(nx + 2) == 1 {
                                        ac i32 = sym_code(si3)
                                        if ac >= 20 {
                                            mk i32 = mem_find(ac - 20, nx + 2)
                                            if mk >= 0 {
                                                cc2 void = gmcode
                                                ar2 void = gmarray
                                                mc i32 = cc2.(i32[512])[mk]
                                                if mc == 10 {
                                                    if ar2.(i32[512])[mk] == 1 { eo("char* ") }
                                                    else { eo("char ") }
                                                } else if mc == 11 {
                                                    eo("char* ")
                                                } else if mc == 12 {
                                                    eo("void* ")
                                                } else {
                                                    ctype(mc)
                                                    espace()
                                                }
                                                etk(nt)
                                                sym_add(nt, mc, 0, 0, vis)
                                                espace()
                                                ec(61)
                                                espace()
                                                gi = nx
                                                expr_assign()
                                                eo(";")
                                                return
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    expr_assign()
    eo(";")
}

func block_main() {
    need_p("{")
    eo("{ __nihao_init(); ")
    skip_nl()
    while ck() != 8 {
        if is_p("}") == 1 {
            adv()
            eo("return 0; }")
            return
        }
        stmt()
        skip_nl()
    }
    eo("return 0; }")
}

func skip_braces() {
    depth i32 = 0
    while ck() != 8 {
        if is_p("{") == 1 { depth = depth + 1 }
        if is_p("}") == 1 {
            depth = depth - 1
            adv()
            if depth <= 0 { return }
        } else {
            adv()
        }
    }
}

/* 该语句是否对 gi 处的变量做写操作（= / op= / ++ / --，深度 0） */
/* 直接重绑定（名字后紧跟 = / op= / ++ / --），而不是写元素/成员 */
func is_rebind(st i32) i32 {
    j i32 = st + 1
    if j >= gntk { return 1 }
    if tk_kind(j) != 6 { return 1 }
    if txt_eq(j, "=") == 1 { return 1 }
    if txt_eq(j, "+=") == 1 { return 1 }
    if txt_eq(j, "-=") == 1 { return 1 }
    if txt_eq(j, "*=") == 1 { return 1 }
    if txt_eq(j, "/=") == 1 { return 1 }
    if txt_eq(j, "%=") == 1 { return 1 }
    return 0
}

func stmt_is_store(st i32) i32 {
    j i32 = st + 1
    depth i32 = 0
    while j < gntk {
        k i32 = tk_kind(j)
        if k == 7 { return 0 }
        if k == 8 { return 0 }
        if k == 6 {
            if txt_eq(j, "(") == 1 { depth = depth + 1 }
            else if txt_eq(j, "[") == 1 { depth = depth + 1 }
            else if txt_eq(j, ")") == 1 { depth = depth - 1 }
            else if txt_eq(j, "]") == 1 { depth = depth - 1 }
            else if txt_eq(j, "++") == 1 { if depth <= 0 { return 1 } }
            else if txt_eq(j, "--") == 1 { if depth <= 0 { return 1 } }
            else if txt_eq(j, ";") == 1 { if depth <= 0 { return 0 } }
            else if txt_eq(j, "=") == 1 { if depth <= 0 { return 1 } }
            else if txt_eq(j, "+=") == 1 { if depth <= 0 { return 1 } }
            else if txt_eq(j, "-=") == 1 { if depth <= 0 { return 1 } }
            else if txt_eq(j, "*=") == 1 { if depth <= 0 { return 1 } }
            else if txt_eq(j, "/=") == 1 { if depth <= 0 { return 1 } }
            else if txt_eq(j, "%=") == 1 { if depth <= 0 { return 1 } }
        }
        j = j + 1
    }
    return 0
}

func skip_parens() {
    depth i32 = 0
    while ck() != 8 {
        if is_p("(") == 1 { depth = depth + 1 }
        if is_p(")") == 1 {
            depth = depth - 1
            adv()
            if depth <= 0 { return }
        } else {
            adv()
        }
    }
}

func eat_rparen() {
    if is_p(")") == 1 { adv() }
}

func emit_if() {
    eo("if")
    espace()
    adv()
    skip_nl()
    need_p("(")
    ec(40)
    expr_assign()
    eat_rparen()
    ec(41)
    espace()
    skip_nl()
    block()
    skip_nl()
    if is_kw("else") == 1 {
        eo(" else ")
        adv()
        skip_nl()
        if is_kw("if") == 1 {
            emit_if()
        } else {
            block()
        }
    }
}

/* while → while (1) { T __isN = (cond); if (!__isN) break; ... }，支持 is 模式 */
func emit_while() {
    adv()
    skip_nl()
    need_p("(")
    gseq = gseq + 1
    isv i32 = gseq
    eo("while (1) { int64_t __is")
    enum_i(isv)
    eo(" = (")
    expr_assign()
    eat_rparen()
    eo("); if (!__is")
    enum_i(isv)
    eo(") break; ")
    skip_nl()
    /* 记当前 is 变量编号 */
    a void = gisn
    a.(i32[64])[gloop] = isv
    gloop = gloop + 1
    block()
    gloop = gloop - 1
    espace()
    ec(125)
}

func emit_do() {
    /* 规范：do 是 while 的别名（前测循环），不是 C 的 do-while */
    adv()
    skip_nl()
    gseq = gseq + 1
    isv i32 = gseq
    eo("while (1) { int64_t __is")
    enum_i(isv)
    eo(" = (")
    need_p("(")
    expr_assign()
    eo("); if (!__is")
    enum_i(isv)
    eo(") break; ")
    need_p(")")
    skip_nl()
    a void = gisn
    a.(i32[64])[gloop] = 0 - 1
    gloop = gloop + 1
    block()
    gloop = gloop - 1
    espace()
    ec(125)
}

func emit_for() {
    adv()
    skip_nl()
    eo("for (")
    need_p("(")
    /* init */
    skip_nl()
    if is_p(";") == 0 {
        if decl_start(gi) == 1 {
            emit_for_decl()
        } else {
            /* `for i = 0; ...`：i 未声明时补成 int64_t 声明 */
            if ck() == 1 {
                if tk_kind(gi + 1) == 6 {
                    if txt_eq(gi + 1, "=") == 1 {
                        if sym_find(gi) < 0 {
                            nt2 i32 = gi
                            eo("int64_t ")
                            etk(nt2)
                            sym_add(nt2, 4, 0, 0, 4)
                            espace() ec(61) espace()
                            gi = gi + 2
                            expr_assign()
                            need_p(";")
                            eo("; ")
                            skip_nl()
                            if is_p(";") == 0 { expr_assign() }
                            eo("; ")
                            need_p(";")
                            skip_nl()
                            if is_p("{") == 0 { expr_assign() }
                            eo(") ")
                            skip_nl()
                            gloop = gloop + 1
                            block()
                            gloop = gloop - 1
                            return
                        }
                    }
                }
            }
            expr_assign()
        }
    }
    eo("; ")
    need_p(";")
    skip_nl()
    if is_p(";") == 0 { expr_assign() }
    eo("; ")
    need_p(";")
    skip_nl()
    if is_p("{") == 0 { expr_assign() }
    eo(") ")
    skip_nl()
    gloop = gloop + 1
    block()
    gloop = gloop - 1
}

/* for 的 init 声明：name T = v */
func emit_for_decl() {
    nt i32 = gi
    adv()
    skip_nl()
    c i32 = 0
    if is_p("(") == 1 {
        adv()
        c = code_of(gi)
        adv()
        need_p(")")
    } else {
        c = code_of(gi)
        adv()
    }
    ctype(c)
    espace()
    etk(nt)
    d i32 = skip_dims()
    sym_add(nt, c, d, 0, 4)
    if is_p("=") == 1 {
        espace() ec(61) espace()
        adv()
        expr_assign()
    }
    while is_p("[") == 1 { adv() }
}

func emit_switch() {
    adv()
    skip_nl()
    eo("switch (")
    need_p("(")
    expr_assign()
    eo(") ")
    need_p(")")
    skip_nl()
    need_p("{")
    eo("{")
    skip_nl()
    while ck() != 8 {
        skip_nl()
        if is_p("}") == 1 { adv() break }
        if is_kw("case") == 1 {
            adv()
            eo("case ")
            expr_assign()
            eo(": ")
            need_p(":")
            skip_nl()
            while ck() != 8 {
                if is_kw("case") == 1 { break }
                if is_kw("default") == 1 { break }
                if is_p("}") == 1 { break }
                stmt()
                skip_nl()
            }
            eo("break; ")
            continue
        }
        if is_kw("default") == 1 {
            adv()
            eo("default: ")
            need_p(":")
            continue
        }
        stmt()
        skip_nl()
    }
    eo("}")
}

func emit_return() {
    adv()
    skip_nl()
    if is_p(";") == 1 { eo("return;") adv() return }
    if is_p("}") == 1 { eo("return;") return }
    if ck() == 7 { eo("return;") return }
    if ck() == 8 { eo("return;") return }
    if is_p("{") == 1 {
        /* return {a, b} → return (T){a, b}; */
        eo("return (")
        if gret >= 20 { ctype(gret) } else { eo("int64_t") }
        eo(")")
        ec(123)
        adv()
        skip_nl()
        if is_p("}") == 0 {
            expr_assign()
            while eat_p(",") == 1 {
                ec(44)
                espace()
                skip_nl()
                expr_assign()
            }
        }
        need_p("}")
        ec(125)
        eo(";")
        return
    }
    eo("return ")
    expr_assign()
    eo(";")
}

/* is 模式：is 5 / is -3 / is +5 / is 1..3 / is -9..-5 / is _ / is _const / is <标识符> */
func emit_is(prev i32) {
    adv()
    skip_nl()
    a void = gisn
    iv i32 = 0
    if gloop > 0 { iv = a.(i32[64])[gloop - 1] }
    if iv <= 0 {
        emsg("'is' pattern match only valid inside while loop body")
        skip_braces()
        return
    }
    if prev == 1 { eo("else ") }
    eo("if (__is")
    enum_i(iv)
    if ck() == 1 {
        if txt_eq(gi, "_") == 1 {
            eo(" || 1) ")
            adv()
            skip_nl()
            block()
            return
        }
        if txt_eq(gi, "_const") == 1 { eo(" == 1) ") adv() skip_nl() block() return }
        if txt_eq(gi, "_flow") == 1 { eo(" == 2) ") adv() skip_nl() block() return }
        if txt_eq(gi, "_static") == 1 { eo(" == 3) ") adv() skip_nl() block() return }
        if txt_eq(gi, "_var") == 1 { eo(" == 4) ") adv() skip_nl() block() return }
        if txt_eq(gi, "_undef") == 1 { eo(" == 0) ") adv() skip_nl() block() return }
        eo(" == ")
        etk(gi)
        eo(") ")
        adv()
        skip_nl()
        block()
        return
    }
    neg1 i32 = 0
    if is_p("-") == 1 { neg1 = 1 adv() }
    else if is_p("+") == 1 { adv() }
    if ck() != 2 {
        emsg("bad 'is' pattern (expected an integer literal)")
        skip_nl()
        skip_braces()
        return
    }
    inum i32 = gi
    adv()
    if is_p("..") == 1 {
        adv()
        neg2 i32 = 0
        if is_p("-") == 1 { neg2 = 1 adv() }
        else if is_p("+") == 1 { adv() }
        eo(" >= ")
        if neg1 == 1 { ec(45) }
        etk(inum)
        eo(" && __is")
        enum_i(iv)
        eo(" <= ")
        if neg2 == 1 { ec(45) }
        if ck() == 2 {
            hi1 i32 = tok_int(gi)
            lo1 i32 = tok_int(inum)
            if neg1 == 1 { lo1 = 0 - lo1 }
            if neg2 == 1 { hi1 = 0 - hi1 }
            if lo1 > hi1 { emsg("empty 'is' range (lower bound greater than upper)") }
            etk(gi)
            adv()
        } else {
            emsg("invalid 'is' range: expected an integer upper bound")
        }
        eo(") ")
    } else {
        eo(" == ")
        if neg1 == 1 { ec(45) }
        etk(inum)
        eo(") ")
    }
    skip_nl()
    block()
}

/* ================= 顶层 ================= */

/* 从 RHS 首个 token 推断「指针指向类型」 */
/* 可见性/所有权转移矩阵：4=var 1=const 2=flow 3=static 0=undef */
func vis_ok(src i32, dst i32) i32 {
    if src == 0 { return 1 }
    if dst == 0 { return 1 }
    if src == dst { return 1 }
    if dst == 1 { return 1 }
    if src == 2 {
        if dst == 4 { return 1 }
        return 0
    }
    if src == 4 {
        if dst == 4 { return 1 }
        return 0
    }
    if src == 3 {
        if dst == 3 { return 1 }
        return 0
    }
    return 0
}

func vis_name(v i32) string {
    if v == 1 { return "const" }
    if v == 2 { return "flow" }
    if v == 3 { return "static" }
    return "var"
}

/* 扫描函数定义的返回可见性（无前缀 → 0） */
func fn_ret_vis(nt i32) i32 {
    j i32 = 0
    while j < gntk {
        if tk_kind(j) == 1 {
            if txt_eq(j, "func") == 1 {
                if j + 1 < gntk {
                    if tok_eq(j + 1, nt) == 1 {
                        k i32 = j + 2
                        depth i32 = 0
                        while k < gntk {
                            if tk_kind(k) == 6 {
                                if txt_eq(k, "(") == 1 { depth = depth + 1 }
                                if txt_eq(k, ")") == 1 {
                                    depth = depth - 1
                                    if depth <= 0 { k = k + 1 break }
                                }
                            }
                            k = k + 1
                        }
                        if k < gntk {
                            if tk_kind(k) == 1 {
                                if txt_eq(k, "const") == 1 { return 1 }
                                if txt_eq(k, "flow") == 1 { return 2 }
                                if txt_eq(k, "static") == 1 { return 3 }
                                if txt_eq(k, "var") == 1 { return 4 }
                            }
                        }
                        return 0
                    }
                }
            }
        }
        j = j + 1
    }
    return 0
}

/* 扫描函数第 ar 个参数的可见性 */
func fn_param_vis(nt i32, ar i32) i32 {
    j i32 = 0
    while j < gntk {
        if tk_kind(j) == 1 {
            if txt_eq(j, "func") == 1 {
                if j + 1 < gntk {
                    if tok_eq(j + 1, nt) == 1 {
                        k i32 = j + 3
                        idx i32 = 0
                        while k < gntk {
                            if tk_kind(k) == 6 {
                                if txt_eq(k, ")") == 1 { return 0 }
                                k = k + 1
                                continue
                            }
                            if tk_kind(k) == 1 {
                                if txt_eq(k, "const") == 1 { if idx == ar { return 1 } k = k + 1 continue }
                                if txt_eq(k, "flow") == 1 { if idx == ar { return 2 } k = k + 1 continue }
                                if txt_eq(k, "static") == 1 { if idx == ar { return 3 } k = k + 1 continue }
                                if txt_eq(k, "var") == 1 { if idx == ar { return 4 } k = k + 1 continue }
                                idx = idx + 1
                            }
                            k = k + 1
                        }
                    }
                }
            }
        }
        j = j + 1
    }
    return 0
}

func first_cap(st i32, en i32) i32 {
    k i32 = st
    while k < en {
        if tk_kind(k) == 6 {
            if txt_eq(k, "[") == 1 {
                v i32 = tok_int(k + 1)
                if v > 0 { return v }
                return 8
            }
        }
        k = k + 1
    }
    return 8
}

func malloc_bytes(i i32) i32 {
    /* i 指向 malloc；解析 malloc(T[N]...) → 字节数 */
    j i32 = i + 2
    c i32 = 0
    if j < gntk { c = code_of(j) }
    if c == 0 { c = 4 }
    j = j + 1
    cnt i32 = 1
    while j < gntk {
        if tk_kind(j) == 6 {
            if txt_eq(j, "]") == 1 { j = j + 1 continue }
            if txt_eq(j, ")") == 1 { break }
            if txt_eq(j, "[") == 1 {
                v i32 = tok_int(j + 1)
                if v > 0 { cnt = cnt * v }
                j = j + 1
                continue
            }
        }
        j = j + 1
    }
    return cnt * size_of_code(c)
}

func infer_pt_at(i i32) i32 {
    if tk_kind(i) == 6 {
        if txt_eq(i, "&") == 1 {
            if tk_kind(i + 1) == 1 {
                sv i32 = sym_find(i + 1)
                if sv >= 0 { return sym_code(sv) }
            }
            return 0
        }
        return 0
    }
    if tk_kind(i) == 1 {
        if txt_eq(i, "malloc") == 1 {
            if tk_kind(i + 1) == 6 {
                if txt_eq(i + 1, "(") == 1 {
                    if code_of(i + 2) > 0 { return code_of(i + 2) }
                }
            }
        }
        sv2 i32 = sym_find(i)
        if sv2 >= 0 {
            if tk_kind(i + 1) == 6 {
                if txt_eq(i + 1, "[") == 1 { return sym_code(sv2) }
            }
            return sym_pt(sv2)
        }
    }
    return 0
}

/* RHS 是否是切片形态（在 '[' 里出现 '..'） */
func rhs_has_slice(i i32) i32 {
    j i32 = i
    depth i32 = 0
    while j < gntk {
        k i32 = tk_kind(j)
        if k == 7 { return 0 }
        if k == 6 {
            if txt_eq(j, "(") == 1 { depth = depth + 1 }
            if txt_eq(j, "[") == 1 { depth = depth + 1 }
            if txt_eq(j, "{") == 1 { depth = depth + 1 }
            if txt_eq(j, ")") == 1 { depth = depth - 1 }
            if txt_eq(j, "]") == 1 { depth = depth - 1 }
            if txt_eq(j, "}") == 1 { depth = depth - 1 }
            if depth > 0 {
                if txt_eq(j, "..") == 1 { return 1 }
            }
            if depth <= 0 {
                if txt_eq(j, ";") == 1 { return 0 }
                if txt_eq(j, "=") == 1 { return 0 }
            }
        }
        j = j + 1
    }
    return 0
}

/* 语句级：一句是否是切片赋值  BASE[lo..hi] = ... */
func is_slice_assign() i32 {
    j i32 = gi
    depth i32 = 0
    dot i32 = 0
    while j < gntk {
        k i32 = tk_kind(j)
        if k == 7 { return 0 }
        if k == 8 { return 0 }
        if k == 6 {
            if txt_eq(j, "(") == 1 { depth = depth + 1 }
            else if txt_eq(j, "[") == 1 { depth = depth + 1 }
            else if txt_eq(j, ")") == 1 { depth = depth - 1 }
            else if txt_eq(j, "]") == 1 { depth = depth - 1 }
            else if txt_eq(j, "..") == 1 {
                if depth > 0 { dot = 1 }
            } else if txt_eq(j, "=") == 1 {
                if depth <= 0 { return dot }
            } else if txt_eq(j, ";") == 1 {
                if depth <= 0 { return 0 }
            }
        }
        j = j + 1
    }
    return 0
}

func emit_slice_elem(k i32) {
    save i32 = gi
    gi = gsbtok
    gslm = 2
    expr_postfix()
    gslm = 0
    eo("[(")
    if gslls >= 0 {
        gi = gslls
        expr_assign()
    } else {
        eo("0")
    }
    eo(")+")
    enum_i(k)
    eo("]")
    gi = save
}

func emit_slice_assign() {
    mark i32 = goutn
    gsbtok = gi
    gslm = 1
    expr_postfix()
    gslm = 0
    goutn = mark
    need_p("=")
    skip_nl()
    if is_p("{") == 1 {
        adv()
        skip_nl()
        k i32 = 0
        while is_p("}") == 0 {
            eo("{ ")
            emit_slice_elem(k)
            eo(" = ")
            expr_assign()
            eo("; } ")
            k = k + 1
            if is_p(",") == 1 { adv() }
            skip_nl()
            if ck() == 8 { break }
        }
        need_p("}")
        gi = gsafter
        return
    }
    if ck() == 4 {
        gseq = gseq + 1
        n i32 = tk_ln(gi) - 1
        hiv i32 = tok_int(gsafter - 2)
        lov i32 = 0
        if gslls >= 0 { lov = tok_int(gslls) }
        if hiv >= lov {
            if n > hiv - lov + 1 {
                print("错误: string needs %d bytes with terminator, slice holds %d\n", n, hiv - lov + 1)
                gerr = gerr + 1
            }
        }
        eo("{ const char* __sl")
        enum_i(gseq)
        eo(" = ")
        etk(gi)
        eo("; ")
        adv()
        k2 i32 = 0
        while k2 < n {
            eo("{ ")
            emit_slice_elem(k2)
            eo(" = __sl")
            enum_i(gseq)
            eo("[")
            enum_i(k2)
            eo("]; } ")
            k2 = k2 + 1
        }
        eo("}")
        gi = gsafter
        return
    }
    eo("{ ")
    emit_slice_elem(0)
    eo(" = ")
    expr_assign()
    eo("; }")
    gi = gsafter
}

func agg_has_default(agg i32) i32 {
    a void = gmagg
    d1 void = gmdef
    k i32 = 0
    while k < gmc {
        if a.(i32[512])[k] == agg {
            if d1.(i32[512])[k] >= 0 { return 1 }
        }
        k = k + 1
    }
    return 0
}

func reset_sel() {
    a void = gsel
    k i32 = 0
    while k < 64 {
        a.(i32[64])[k] = 0
        k = k + 1
    }
}

func mark_pos(p i32) {
    a void = gsel
    if p < 64 { a.(i32[64])[p] = 1 }
}

func mark_name(agg i32, nt i32) {
    mk i32 = mem_find(agg, nt)
    if mk >= 0 {
        ix void = gmidx
        a void = gsel
        i i32 = ix.(i32[512])[mk]
        if i < 64 { a.(i32[64])[i] = 1 }
    }
}

func emit_tok_span(a i32, b i32) {
    k i32 = a
    while k < b {
        etk(k)
        ec(32)
        k = k + 1
    }
}

/* 追加未被覆盖成员的默认值（union 只取首个带默认值的成员） */
func agg_defaults(agg i32, use_sel i32) {
    a void = gmagg
    ix void = gmidx
    nm void = gmname
    d1 void = gmdef
    d2 void = gmdef2
    sel void = gsel
    kd void = gtk2
    isunion i32 = 0
    if kd.(i32[128])[agg] == 2 { isunion = 1 }
    first i32 = gfirst
    emitted i32 = 0
    k i32 = 0
    while k < gmc {
        if a.(i32[512])[k] == agg {
            if d1.(i32[512])[k] >= 0 {
                ok i32 = 1
                if use_sel == 1 {
                    i2 i32 = ix.(i32[512])[k]
                    if i2 < 64 {
                        if sel.(i32[64])[i2] == 1 { ok = 0 }
                    }
                }
                if isunion == 1 {
                    if emitted >= 1 { ok = 0 }
                }
                if ok == 1 {
                    if first == 0 { eo(", ") }
                    eo(".")
                    etk(nm.(i32[512])[k])
                    espace() ec(61) espace()
                    emit_tok_span(d1.(i32[512])[k], d2.(i32[512])[k])
                    first = 0
                    emitted = emitted + 1
                }
            }
        }
        k = k + 1
    }
}

/* '{' 之后、'}' 之前的成员初值（含补默认） */
func emit_agg_items(agg i32) {
    reset_sel()
    posn i32 = 0
    first i32 = 1
    if is_p("}") == 0 {
        while 1 == 1 {
            if first == 0 { eo(", ") }
            first = 0
            if is_p(".") == 1 {
                adv()
                if ck() == 1 { mark_name(agg, gi) }
                eo(".")
                etk(gi)
                adv()
                need_p("=")
                espace() ec(61) espace()
                expr_assign()
            } else {
                mark_pos(posn)
                posn = posn + 1
                expr_assign()
            }
            if is_p(",") == 0 { break }
            adv()
            skip_nl()
            if ck() == 8 { break }
        }
    }
    need_p("}")
    gfirst = first
    agg_defaults(agg, 1)
}

/* 无源码初值时：按默认值直接产出元素 */
func emit_agg_elem_defs(agg i32) {
    eo("{ ")
    gfirst = 1
    if agg_has_default(agg) == 1 { agg_defaults(agg, 0) } else { ec(48) }
    eo(" }")
}

func emit_agg_elem(agg i32) {
    need_p("{")
    eo("{ ")
    skip_nl()
    emit_agg_items(agg)
    eo(" }")
}

func dims_product(st i32, en i32) i32 {
    total i32 = 1
    k i32 = st
    while k < en {
        if tk_kind(k) == 6 {
            if txt_eq(k, "[") == 1 {
                v i32 = tok_int(k + 1)
                if v <= 0 {
                    if tk_kind(k + 1) == 6 {
                        if txt_eq(k + 1, "]") == 1 { v = 8 }
                    }
                }
                if v <= 0 { v = 8 }
                total = total * v
            }
        }
        k = k + 1
    }
    if total <= 0 { total = 1 }
    return total
}

func emit_aggarr_init(agg i32, total i32) {
    need_p("{")
    ec(123)
    skip_nl()
    nested i32 = 0
    given i32 = 0
    if is_p("}") == 0 {
        if is_p("{") == 1 { nested = 1 }
        if nested == 1 {
            first i32 = 1
            while 1 == 1 {
                if first == 0 { eo(", ") }
                first = 0
                if is_p("{") == 1 {
                    emit_agg_elem(agg)
                    given = given + 1
                } else {
                    emit_init_item()
                }
                if is_p(",") == 0 { break }
                adv()
                skip_nl()
                if ck() == 8 { break }
            }
        } else {
            first2 i32 = 1
            while is_p("}") == 0 {
                if first2 == 0 { eo(", ") }
                first2 = 0
                emit_init_item()
                if is_p(",") == 0 { break }
                adv()
                skip_nl()
                if ck() == 8 { break }
            }
        }
    }
    need_p("}")
    if nested == 1 {
        while given < total {
            eo(", ")
            emit_agg_elem_defs(agg)
            given = given + 1
        }
    }
    ec(125)
}

/* 把 dstart..dend 的维度长度收进 gdl[] / gdn */
func collect_dims(st i32, en i32) {
    a void = gdl
    gdn = 0
    k i32 = st
    while k < en {
        if tk_kind(k) == 6 {
            if txt_eq(k, "[") == 1 {
                v i32 = tok_int(k + 1)
                if v <= 0 {
                    if tk_kind(k + 1) == 6 {
                        if txt_eq(k + 1, "]") == 1 { v = 8 }
                    }
                }
                if v <= 0 { v = 8 }
                if gdn < 8 {
                    a.(i32[16])[gdn] = v
                    gdn = gdn + 1
                }
            }
        }
        k = k + 1
    }
}

func emit_nd_defaults(agg i32, level i32) {
    if level >= gdn {
        emit_agg_elem_defs(agg)
        return
    }
    a void = gdl
    cnt i32 = a.(i32[16])[level]
    eo("{ ")
    k i32 = 0
    while k < cnt {
        if k > 0 { eo(", ") }
        emit_nd_defaults(agg, level + 1)
        k = k + 1
    }
    eo(" }")
}

func emit_decl(vis i32) {
    pend_src i32 = -1
    pend_st i32 = 0
    nt i32 = gi
    adv()
    skip_nl()
    c i32 = 0
    if is_p("(") == 1 {
        adv()
        c = code_of(gi)
        adv()
        need_p(")")
    } else {
        c = code_of(gi)
        adv()
    }
    if c == 0 { c = 4 }
    if is_p("(") == 1 { emit_fnptr_decl(nt, c, vis) return }

    dstart i32 = gi
    d i32 = skip_dims()
    dend i32 = gi
    fe i32 = first_dim_empty(dstart, dend)
    asptr i32 = 0
    if c == 12 {
        if d > 0 {
            if is_p("=") == 1 {
                if tk_kind(gi + 1) == 1 {
                    if txt_eq(gi + 1, "malloc") == 1 { asptr = 1 }
                }
            }
        }
    }
    si i32 = sym_add(nt, c, d, 0, vis)
    if fe == 1 {
        if c == 10 { gdims_set(si, 100 + d) }
    }
    if c == 12 {
        if is_p("=") == 1 {
            ptv i32 = infer_pt_at(gi + 1)
            if ptv > 0 { sym_set_pt(si, ptv) }
            if tk_kind(gi + 1) == 1 {
                if txt_eq(gi + 1, "malloc") == 1 {
                    sc9 void = gslice
                    sc9.(i32[512])[si] = malloc_bytes(gi + 1)
                }
            }
        }
    }

    if vis == 1 { eo("const ") }
    if c == 11 {
        eo("char* ")
    } else if c == 12 {
        if asptr == 1 {
            if d >= 2 { eo("void* (*") } else { eo("void** ") }
        } else { eo("void* ") }
    } else if c == 10 {
        if d > 0 {
            if fe == 1 { eo("char* ") } else { eo("char ") }
        } else {
            eo("char ")
        }
    } else {
        ctype(c)
        espace()
    }
    etk(nt)
    gi = dstart
    if fe == 0 {
        if asptr == 1 {
            if d >= 2 {
                /* 跳过首维，其余维度跟在名字后 */
                eo(")")
                skip_first_dim()
                emit_dims_c(c)
            } else {
                skip_dims()
            }
        } else {
            emit_dims_c(c)
        }
    } else {
        skip_dims()
    }
    gi = dend

    if is_p("=") == 1 {
        adv()
        skip_nl()
        /* 顶层非常量初值（malloc/create 等调用）：C 文件作用域不允许，
         * 挪进 __nihao_init()，main 开头调用 */
        if ck() == 1 {
            if tk_kind(gi + 1) == 6 {
                if txt_eq(gi + 1, "(") == 1 {
                    rv9 i32 = fn_ret_vis(gi)
                    if rv9 == 1 {
                        if vis_ok(1, vis) == 0 {
                            print("错误: cannot assign %s() return (visibility const): target lifetime shorter than source\n", gout)
                            gerr = gerr + 1
                        }
                    }
                    if rv9 == 2 {
                        if vis_ok(2, vis) == 0 {
                            print("错误: cannot assign %s() return (visibility flow): target lifetime shorter than source\n", gout)
                            gerr = gerr + 1
                        }
                    }
                    if rv9 == 3 {
                        if vis_ok(3, vis) == 0 {
                            print("错误: cannot assign %s() return (visibility static): target lifetime shorter than source\n", gout)
                            gerr = gerr + 1
                        }
                    }
                }
            }
            if tk_kind(gi + 1) != 6 {
                sv12 i32 = sym_find(gi)
                if sv12 >= 0 {
                    if vis_ok(sym_vis(sv12), vis) == 0 {
                        tok_cstr(gi)
                        print("错误: cannot assign %s (visibility %s) to a %s target\n", gout, vis_name(sym_vis(sv12)), vis_name(vis))
                        gerr = gerr + 1
                    }
                    if sym_vis(sv12) == 2 {
                        st9 void = gstate
                        if vis == 4 {
                            pend_src = sv12
                            pend_st = 1
                            glastfrz = sv12
                        } else if vis == 2 {
                            if st9.(i32[512])[sv12] == 1 {
                                emsg("cannot transfer ownership of a frozen pointer")
                            } else {
                                pend_src = sv12
                                pend_st = 2
                            }
                        }
                    }
                }
            }
        }
        if gtop == 1 {
            if ck() == 1 {
                if tk_kind(gi + 1) == 6 {
                    if txt_eq(gi + 1, "(") == 1 {
                        if ginitn < 64 {
                            st8 i32 = gi
                            depth8 i32 = 0
                            while ck() != 8 {
                                if is_p("(") == 1 { depth8 = depth8 + 1 }
                                if is_p(")") == 1 { depth8 = depth8 - 1 }
                                if depth8 <= 0 {
                                    if tk_kind(gi) == 7 { break }
                                    if is_p(";") == 1 { break }
                                }
                                adv()
                            }
                            a9 void = giname
                            b9 void = gis
                            c9 void = gie
                            a9.(i32[64])[ginitn] = nt
                            b9.(i32[64])[ginitn] = st8
                            c9.(i32[64])[ginitn] = gi
                            ginitn = ginitn + 1
                        }
                        espace() ec(61) espace() ec(48)
                        eo(";")
                        return
                    }
                }
            }
        }
        /* 切片读入声明数组：T x[N] = BASE[lo..hi] → memcpy */
        if d > 0 {
            if rhs_has_slice(gi) == 1 {
                mark3 i32 = goutn
                gsbtok = gi
                gslm = 1
                expr_postfix()
                gslm = 0
                goutn = mark3
                eo("; memcpy(")
                etk(nt)
                eo(", (")
                save2 i32 = gi
                gi = gsbtok
                gslm = 2
                expr_postfix()
                gslm = 0
                eo(") + (")
                if gslls >= 0 {
                    gi = gslls
                    expr_assign()
                } else {
                    eo("0")
                }
                eo("), sizeof(")
                etk(nt)
                eo("));")
                gi = gsafter
                return
            }
        }
        espace() ec(61) espace()
        if is_p("{") == 1 {
            if c >= 20 {
                if d == 0 {
                    ec(123)
                    adv()
                    skip_nl()
                    emit_agg_items(c - 20)
                    ec(125)
                } else {
                    emit_aggarr_init(c - 20, dims_product(dstart, dend))
                }
            } else {
                ec(123)
                adv()
                skip_nl()
                if is_p("}") == 0 {
                    emit_init_item()
                    while eat_p(",") == 1 {
                        ec(44)
                        espace()
                        skip_nl()
                        emit_init_item()
                    }
                }
                need_p("}")
                ec(125)
            }
        } else if ck() == 4 {
            if ((c == 11) || (c == 10 && d > 0 && fe == 1)) {
                if vis != 1 { eo("__nihao_strdup(") }
                etk(gi)
                adv()
                if vis != 1 { eo(")") }
            } else if d > 0 {
                if c != 10 {
                    tok_cstr(nt)
                    print("错误: cannot initialize array '%s' with a string literal\n", gout)
                    gerr = gerr + 1
                } else {
                    cap1 i32 = first_cap(dstart, dend)
                    need1 i32 = tk_ln(gi) - 1
                    if need1 > cap1 {
                        tok_cstr(nt)
                        print("错误: string needs %d bytes with terminator, array '%s' holds %d\n", need1, gout, cap1)
                        gerr = gerr + 1
                    }
                }
            }
            etk(gi)
            adv()
        } else {
            expr_assign()
        }
    } else {
        if asptr == 1 { espace() ec(61) espace() eo("0") }
        else if c >= 20 {
            espace() ec(61) espace()
            if d == 0 {
                ec(123)
                reset_sel()
                gfirst = 1
                if agg_has_default(c - 20) == 1 { agg_defaults(c - 20, 0) } else { ec(48) }
                ec(125)
            } else {
                collect_dims(dstart, dend)
                if dims_product(dstart, dend) * agg_mcount(c - 20) > 1024 {
                    emsg("aggregate array is too large to expand its member defaults")
                }
                if gdn >= 2 {
                    emit_nd_defaults(c - 20, 0)
                } else {
                    ec(123)
                    total i32 = dims_product(dstart, dend)
                    kk i32 = 0
                    while kk < total {
                        if kk > 0 { eo(", ") }
                        emit_agg_elem_defs(c - 20)
                        kk = kk + 1
                    }
                    ec(125)
                }
            }
        }
        else if d > 0 { espace() ec(61) espace() ec(123) ec(48) ec(125) }
        else { espace() ec(61) espace() ec(48) }
    }
    if pend_src >= 0 {
        sv14 void = gstate
        sv14.(i32[512])[pend_src] = pend_st
    }
    eo(";")
}

func emit_init_item() {
    if is_p(".") == 1 {
        ec(46)
        adv()
        etk(gi)
        adv()
        espace() ec(61) espace()
    }
    if is_p("{") == 1 {
        ec(123)
        adv()
        skip_nl()
        if is_p("}") == 0 {
            emit_init_item()
            while eat_p(",") == 1 {
                ec(44)
                espace()
                emit_init_item()
            }
        }
        need_p("}")
        ec(125)
        return
    }
    expr_assign()
}

func emit_multi_decl(vis i32) {
    adv()
    need_p("{")
    skip_nl()
    gmdn = 0
    while ck() != 8 {
        skip_nl()
        if is_p("}") == 1 { break }
        if ck() != 1 { adv() continue }
        ntk i32 = gi
        adv()
        st i32 = gi
        en i32 = gi
        if is_p("=") == 1 {
            adv()
            skip_nl()
            st = gi
            depth i32 = 0
            while ck() != 8 {
                if is_p("(") == 1 { depth = depth + 1 }
                if is_p("[") == 1 { depth = depth + 1 }
                if is_p("{") == 1 { depth = depth + 1 }
                if is_p(")") == 1 { depth = depth - 1 }
                if is_p("]") == 1 { depth = depth - 1 }
                if is_p("}") == 1 {
                    if depth <= 0 { break }
                    depth = depth - 1
                }
                if depth <= 0 {
                    if is_p(",") == 1 { break }
                }
                adv()
            }
            en = gi
        }
        if gmdn < 16 {
            gmd_set(gmdn, ntk, st, en)
            gmdn = gmdn + 1
        }
        if is_p(",") == 1 { adv() }
        skip_nl()
    }
    need_p("}")
    skip_nl()
    c i32 = code_of(gi)
    if c == 0 { c = 4 }
    adv()
    dstart i32 = gi
    d i32 = skip_dims()
    dend i32 = gi
    fe i32 = first_dim_empty(dstart, dend)
    k i32 = 0
    while k < gmdn {
        nt i32 = gmd_name(k)
        if vis == 1 { eo("const ") }
        if c == 10 {
            if d > 0 {
                if fe == 1 {
                    eo("char* ")
                    etk(nt)
                } else {
                    eo("char ")
                    etk(nt)
                    gi = dstart
                    emit_dims_c(c)
                    gi = dend
                }
            } else {
                eo("char ")
                etk(nt)
            }
        } else if c == 11 {
            eo("char* ")
            etk(nt)
        } else if c == 12 {
            eo("void* ")
            etk(nt)
        } else {
            ctype(c)
            espace()
            etk(nt)
            if d > 0 {
                gi = dstart
                emit_dims_c(c)
                gi = dend
            }
        }
        si4 i32 = sym_add(nt, c, d, 0, vis)
        if c == 10 {
            if d > 0 {
                if fe == 1 { gdims_set(si4, 100 + d) }
            }
        }
        if d > 0 {
            if c == 10 {
                if gmd_s(k) < gmd_e(k) {
                    if tk_kind(gmd_s(k)) != 4 {
                        tok_cstr(nt)
                        print("错误: '%s' has fixed array type but no string literal initializer\n", gout)
                        gerr = gerr + 1
                    } else {
                        cap2 i32 = first_cap(dstart, dend)
                        need2 i32 = tk_ln(gmd_s(k)) - 1
                        if need2 > cap2 {
                            tok_cstr(nt)
                            print("错误: string needs %d bytes with terminator, array '%s' holds %d\n", need2, gout, cap2)
                            gerr = gerr + 1
                        }
                    }
                }
            } else {
                tok_cstr(nt)
                print("错误: '%s' has fixed array type but no string literal initializer\n", gout)
                gerr = gerr + 1
            }
        }
        if gmd_s(k) != gmd_e(k) {
            espace() ec(61) espace()
            if (c == 10) {
                if (d > 0) {
                    if (fe == 1) {
                        if tk_kind(gmd_s(k)) == 4 {
                            if vis != 1 { eo("__nihao_strdup(") }
                            etk(gmd_s(k))
                            if vis != 1 { eo(")") }
                            eo("; ")
                            k = k + 1
                            continue
                        }
                    }
                }
            }
            p2 i32 = gmd_s(k)
            while p2 < gmd_e(k) {
                etk(p2)
                ec(32)
                p2 = p2 + 1
            }
        } else {
            espace() ec(61) espace() ec(48)
        }
        eo("; ")
        k = k + 1
    }
    gi = dend
}

func emit_type_def(kind i32, inbody i32) {
    /* Name struct { ... } / union / enum */
    nt i32 = gi
    adv()
    adv()  /* struct / union / enum */
    skip_nl()
    id i32 = agg_find(nt)
    if id < 0 { id = agg_add(nt, kind) }
    if kind == 3 {
        eo("typedef enum {")
        need_p("{")
        while ck() != 8 {
            if is_p("}") == 1 { adv() break }
            if ck() == 1 { etk(gi) adv() }
            else { etk(gi) adv() }
            if is_p("=") == 1 { espace() ec(61) espace() adv() if ck() == 2 { etk(gi) adv() } else if is_p("-") == 1 { ec(45) adv() etk(gi) adv() } }
            if eat_p(",") == 1 { eo(", ") }
        }
        eo("} ")
        etk(nt)
        eo(";")
        return
    }
    if kind == 1 { eo("typedef struct {") } else { eo("typedef union {") }
    midx i32 = 0
    need_p("{")
    skip_nl()
    while ck() != 8 {
        if is_p("}") == 1 { adv() break }
        if ck() != 1 { adv() continue }
        /* 成员：name TYPE [dims] [:bits] */
        mt i32 = gi
        adv()
        skip_nl()
        c i32 = code_of(gi)
        if c == 0 { c = 4 }
        adv()
        dstart i32 = gi
        d i32 = skip_dims()
        dend i32 = gi
        fe i32 = first_dim_empty(dstart, dend)
        if c == 10 {
            if fe == 1 { eo("char* ") } else { eo("char ") }
        } else if c == 11 {
            eo("char* ")
        } else if c == 12 {
            eo("void* ")
        } else {
            ctype(c)
            espace()
        }
        etk(mt)
        gi = dstart
        if fe == 0 { emit_dims_c(c) } else { skip_dims() }
        gi = dend
        bw i32 = 0
        if is_p(":") == 1 {
            ec(58)
            adv()
            bw = tok_int(gi)
            etk(gi)
            adv()
        }
        /* 成员默认值：= expr（到行尾） */
        ds2 i32 = -1
        de2 i32 = -1
        if is_p("=") == 1 {
            adv()
            skip_nl()
            ds2 = gi
            while ck() != 8 {
                if tk_kind(gi) == 7 { break }
                if is_p("}") == 1 { break }
                adv()
            }
            de2 = gi
        }
        if gskipdefs == 0 {
            mem_add(id, midx, mt, c, (d > 0 || c == 11) ? 1 : 0, ds2, de2)
            mem_set_bit(gmc - 1, bw)
        }
        midx = midx + 1
        eo("; ")
        skip_nl()
    }
    if kind == 1 { eo("} ") } else { eo("} ") }
    etk(nt)
    eo(";")
}

/* 函数定义：func name(params) [vis] ret { body } */
func emit_func(haskw i32) {
    sav_gn i32 = gn
    rvis0 i32 = 0
    if haskw == 0 {
        if gretvis == 1 { rvis0 = 1 }
        if gretvis == 2 { rvis0 = 2 }
        if gretvis == 3 { rvis0 = 3 }
    }
    gretvis = 0
    if haskw == 1 { adv()  /* func */ }
    skip_nl()
    if ck() != 1 { return }
    nt i32 = gi
    adv()
    skip_nl()
    need_p("(")
    rcode i32 = 12
    /* 参数：先把参数区文本收集到临时区，再输出 */
    mark i32 = goutn
    eo("(")
    first i32 = 1
    while ck() != 8 {
        skip_nl()
        if is_p(")") == 1 { adv() break }
        /* 参数前缀 */
        pv i32 = 4
        if is_kw("const") == 1 { pv = 1 adv() }
        else if is_kw("flow") == 1 { pv = 2 adv() }
        else if is_kw("static") == 1 { pv = 3 adv() }
        else if is_kw("var") == 1 { pv = 4 adv() }
        if ck() != 1 { adv() continue }
        pt i32 = gi
        adv()
        skip_nl()
        c i32 = code_of(gi)
        if c == 0 { c = 4 }
        adv()
        d i32 = skip_dims()
        sym_add(pt, c, d, 0, pv)
        if first == 0 { eo(", ") }
        first = 0
        if c == 11 { eo("char* ") }
        else if c == 12 { eo("void* ") }
        else if c == 10 {
            if d > 0 { eo("char* ") } else { eo("char ") }
        } else {
            ctype(c)
            espace()
        }
        etk(pt)
        if d > 0 { ec(91) ec(93) }
        if is_p(",") == 1 { adv() }
    }
    /* 返回类型 */
    skip_nl()
    rvis i32 = rvis0
    if is_p("{") == 0 {
        /* 可选可见性前缀：flow/const/static 的 void 返回表示指针 */
        if is_kw("const") == 1 { rvis = 1 adv() }
        else if is_kw("flow") == 1 { rvis = 2 adv() }
        else if is_kw("static") == 1 { rvis = 3 adv() }
        else if is_kw("var") == 1 { rvis = 4 adv() }
        rcode = code_of(gi)
        if rcode == 0 { rcode = 12 }
        adv()
        d2 i32 = skip_dims()
    }
    /* 输出：ret name(args) */
    /* 目前 args 已写入输出，需重排：先把 args 挪到临时区 */
    nargs i32 = goutn - mark - 1
    tmp i32 = 520000
    o void = gout
    k i32 = 0
    while k < nargs {
        o.(i8[524288])[tmp + k] = o.(i8[524288])[mark + 1 + k]
        k = k + 1
    }
    goutn = mark
    if txt_eq(nt, "main") == 1 { eo("int ") }
    else if rcode == 12 { if rvis > 0 { eo("void* ") } else { eo("void ") } }
    else {
        if rcode == 11 { eo("char* ") }
        else if rcode == 10 { eo("char ") }
        else { ctype(rcode) espace() }
    }
    etk(nt)
    ec(40)
    k = 0
    while k < nargs {
        ec(o.(i8[524288])[tmp + k])
        k = k + 1
    }
    ec(41)
    espace()
    gret = rcode
    skip_nl()
    if txt_eq(nt, "main") == 1 { block_main() } else { block() }
    gn = sav_gn
    eol()
}

/* 预扫描：为所有函数发一条无参原型（避免「先调用后定义」的隐式声明） */
/* 预登记聚合类型名（原型需要知道返回类型） */
func pre_aggs() {
    save i32 = gi
    gi = 0
    while ck() != 8 {
        if ck() == 1 {
            ni i32 = gi + 1
            if is_kw_at(ni, "struct") == 1 { agg_add(gi, 1) }
            else if is_kw_at(ni, "union") == 1 { agg_add(gi, 2) }
            else if is_kw_at(ni, "enum") == 1 { agg_add(gi, 3) }
        }
        adv()
    }
    gi = save
}

/* 第一遍：所有类型定义（Name struct/union/enum、alias）先出到最前面 */
func emit_typedefs() {
    save i32 = gi
    gi = 0
    while ck() != 8 {
        if ck() == 1 {
            ni9 i32 = gi + 1
            if is_kw_at(ni9, "struct") == 1 { emit_type_def(1, 0) continue }
            if is_kw_at(ni9, "union") == 1 { emit_type_def(2, 0) continue }
            if is_kw_at(ni9, "enum") == 1 { emit_type_def(3, 0) continue }
            if txt_eq(gi, "alias") == 1 {
                adv()
                skip_nl()
                nt9 i32 = gi
                adv()
                if is_p("=") == 1 { adv() }
                cc9 i32 = code_of(gi)
                if cc9 == 0 { cc9 = 4 }
                adv()
                eo("typedef ")
                ctype(cc9)
                espace()
                etk(nt9)
                eo("; ")
                continue
            }
        }
        adv()
    }
    gi = save
}

func emit_protos() {
    save i32 = gi
    gi = 0
    while ck() != 8 {
        skip_nl()
        if is_kw("func") == 1 {
            adv()
            skip_nl()
            if ck() == 1 {
                nt i32 = gi
                adv()
                skip_nl()
                /* 参数类型（C 原型） */
                mark i32 = goutn
                if is_p("(") == 1 {
                    depth i32 = 1
                    adv()
                    first i32 = 1
                    while depth > 0 && ck() != 8 {
                        if is_p("(") == 1 { depth = depth + 1 adv() continue }
                        if is_p(")") == 1 {
                            depth = depth - 1
                            adv()
                            continue
                        }
                        if depth == 1 {
                            if is_kw("const") == 1 { adv() continue }
                            if is_kw("flow") == 1 { adv() continue }
                            if is_kw("static") == 1 { adv() continue }
                            if is_kw("var") == 1 { adv() continue }
                            if ck() == 1 {
                                pc i32 = code_of(gi)
                                if pc > 0 {
                                    adv()
                                } else {
                                    adv()
                                    skip_nl()
                                    pc = code_of(gi)
                                    if pc == 0 { pc = 4 }
                                    adv()
                                }
                                pd i32 = skip_dims()
                                if first == 0 { eo(", ") }
                                first = 0
                                if pc == 12 { eo("void*") }
                                else if pc == 11 { eo("char*") }
                                else if pc == 10 {
                                    if pd > 0 { eo("char*") } else { eo("char") }
                                } else {
                                    ctype(pc)
                                }
                                if is_p(",") == 1 { adv() }
                                continue
                            }
                        }
                        adv()
                    }
                }
                nargs i32 = goutn - mark
                tmp i32 = 510000
                o void = gout
                kz i32 = 0
                while kz < nargs {
                    o.(i8[524288])[tmp + kz] = o.(i8[524288])[mark + kz]
                    kz = kz + 1
                }
                goutn = mark
                /* 返回类型 */
                skip_nl()
                rv i32 = 0
                if is_kw("const") == 1 { rv = 1 adv() }
                else if is_kw("flow") == 1 { rv = 2 adv() }
                else if is_kw("static") == 1 { rv = 3 adv() }
                else if is_kw("var") == 1 { rv = 4 adv() }
                rc i32 = code_of(gi)
                if rc > 0 { adv() }
                if rc == 0 { rc = 12 }
                /* 先写返回类型 + 名字，再回放参数类型 */
                if txt_eq(nt, "main") == 1 { eo("int ") }
                else if rc == 12 { if rv > 0 { eo("void* ") } else { eo("void ") } }
                else if rc == 11 { eo("char* ") }
                else if rc == 10 { eo("char ") }
                else { ctype(rc) espace() }
                etk(nt)
                ec(40)
                kz = 0
                while kz < nargs {
                    ec(o.(i8[524288])[tmp + kz])
                    kz = kz + 1
                }
                eo("); ")
            }
        } else {
            adv()
        }
    }
    gi = save
}

/* use NAME[.NAME]：把模块源文件当作同一输出里的顶层声明内联（单层） */
func use_module() {
    adv()
    /* 组路径：<BOOT_INC>/a/b.nc */
    path char[256]
    pi i32 = 0
    inc void = getenv("BOOT_INC")
    if inc != 0 {
        k i32 = 0
        while inc.(i8[256])[k] != 0 {
            if pi < 240 {
                path[pi] = inc.(i8[256])[k]
                pi = pi + 1
            }
            k = k + 1
        }
        path[pi] = 47
        pi = pi + 1
    }
    while ck() == 1 {
        st i32 = tk_st(gi)
        n i32 = tk_ln(gi)
        k2 i32 = 0
        while k2 < n {
            if pi < 240 {
                path[pi] = sch(st + k2)
                pi = pi + 1
            }
            k2 = k2 + 1
        }
        adv()
        if is_p(".") == 1 {
            if pi < 240 {
                path[pi] = 47
                pi = pi + 1
            }
            adv()
        } else {
            break
        }
    }
    if pi < 244 {
        path[pi] = 46
        path[pi + 1] = 110
        path[pi + 2] = 99
        path[pi + 3] = 0
    }
    f void = fopen(path, "r")
    if f == 0 {
        /* 找不到模块（如 stdio）：当作空导入 */
        skip_line()
        return
    }
    save_src i64 = gsrc
    save_len i32 = gsrcn
    save_tk i64 = gtk
    save_ntk i32 = gntk
    save_gi i32 = gi
    save_gn i32 = gn
    save_nt2 i32 = gnt
    save_mc i32 = gmc
    gsrc = gmsrc
    gtk = gmtk
    gntk = 0
    gsrcn = fread(gmsrc, 1, 524287, f)
    fclose(f)
    lex()
    gi = 0
    while ck() != 8 {
        top()
        eol()
    }
    gsrc = save_src
    gsrcn = save_len
    gtk = save_tk
    gntk = save_ntk
    gi = save_gi
    gn = save_gn
    gnt = save_nt2
    gmc = save_mc
}

func top() {
    skip_nl()
    if ck() == 8 { return }
    if is_kw("module") == 1 { skip_line() return }
    if is_kw("use") == 1 { use_module() return }
    if is_kw("link") == 1 { skip_line() return }
    if is_kw("linkas") == 1 { emsg("linkas 尚未实现（静态库导出命名）") skip_line() return }
    if is_kw("import") == 1 { skip_line() return }
    if is_kw("cooking") == 1 { cooking_block() return }
    if is_kw("static_assert") == 1 { adv() skip_parens() return }
    if is_p("[[") == 1 { skip_attr() return }
    if is_p("[") == 1 {
        /* [[attr]] 词法上是 [ [ */
        if tk_kind(gi + 1) == 6 {
            if txt_eq(gi + 1, "[") == 1 { skip_attr() return }
        }
    }
    if is_kw("alias") == 1 {
        adv()
        skip_nl()
        nt i32 = gi
        adv()
        /* alias X = T */
        if is_p("=") == 1 { adv() }
        c i32 = code_of(gi)
        if c == 0 { c = 4 }
        adv()
        eo("typedef ")
        ctype(c)
        espace()
        etk(nt)
        eo(";")
        return
    }
    if is_kw("func") == 1 { emit_func(1) return }
    /* 顶层类型定义 Name struct/union/enum */
    if ck() == 1 {
        ni i32 = gi + 1
        if is_kw_at(ni, "struct") == 1 {
            if gskipdefs == 1 { mk7 i32 = goutn emit_type_def(1, 0) goutn = mk7 return }
            emit_type_def(1, 0)
            return
        }
        if is_kw_at(ni, "union") == 1 {
            if gskipdefs == 1 { mk7b i32 = goutn emit_type_def(2, 0) goutn = mk7b return }
            emit_type_def(2, 0)
            return
        }
        if is_kw_at(ni, "enum") == 1 {
            if gskipdefs == 1 { mk7c i32 = goutn emit_type_def(3, 0) goutn = mk7c return }
            emit_type_def(3, 0)
            return
        }
    }
    /* 顶层变量 */
    vis i32 = 4
    if is_kw("const") == 1 { vis = 1 adv() }
    else if is_kw("flow") == 1 { vis = 2 adv() }
    else if is_kw("static") == 1 { vis = 3 adv() }
    else if is_kw("var") == 1 { vis = 4 adv() }
    /* 带可见性前缀的函数定义：flow create() void { ... } */
    if ck() == 1 {
        if tk_kind(gi + 1) == 6 {
            if txt_eq(gi + 1, "(") == 1 {
                gretvis = vis
                emit_func(0)
                return
            }
        }
    }
    if decl_start(gi) == 1 {
        gtop = 1
        emit_decl(vis)
        gtop = 0
        return
    }
    /* 其他：跳一行 */
    skip_line()
}

func is_kw_at(i i32, s void) i32 {
    if tk_kind(i) != 1 { return 0 }
    return txt_eq(i, s)
}

func skip_line() {
    while ck() != 8 {
        if tk_kind(gi) == 7 { adv() return }
        adv()
    }
}

func attr_known(i i32) i32 {
    if txt_eq(i, "export") == 1 { return 1 }
    if txt_eq(i, "inline") == 1 { return 1 }
    if txt_eq(i, "local") == 1 { return 1 }
    if txt_eq(i, "weak") == 1 { return 1 }
    if txt_eq(i, "used") == 1 { return 1 }
    if txt_eq(i, "unused") == 1 { return 1 }
    return 0
}

func skip_attr() {
    /* 取属性名做白名单校验：[[nope]] → unknown bracket attribute 'nope' */
    pk i32 = gi
    while tk_kind(pk) != 8 {
        if tk_kind(pk) == 6 {
            if txt_eq(pk, "[") == 1 { pk = pk + 1 continue }
            if txt_eq(pk, "]") == 1 { break }
        }
        if tk_kind(pk) == 1 {
            if attr_known(pk) == 0 {
                tok_cstr(pk)
                print("错误: unknown bracket attribute '%s'\n", gout)
                gerr = gerr + 1
            }
            break
        }
        pk = pk + 1
    }
    depth i32 = 0
    while ck() != 8 {
        if is_p("[") == 1 { depth = depth + 1 }
        if is_p("]") == 1 {
            depth = depth - 1
            adv()
            if depth <= 0 { return }
        } else {
            adv()
        }
    }
}

/* ================= 驱动 ================= */

func etk_dbg(i i32) {
    st i32 = tk_st(i)
    n i32 = tk_ln(i)
    k i32 = 0
    while k < n {
        ec(sch(st + k))
        k = k + 1
    }
    o void = gout
    o.(i8[524288])[goutn] = 0
    print("  %d  %s\n", tk_kind(i), o)
    goutn = 0
}

func main() {
    gsrc = malloc(i8[524288])
    gtk = malloc(i32[1048576])
    gout = malloc(i8[524288])
    gnames = malloc(i32[512])
    gtypes = malloc(i32[512])
    gdims = malloc(i32[512])
    gpt = malloc(i32[512])
    gvis = malloc(i32[512])
    gtn = malloc(i32[128])
    gtk2 = malloc(i32[128])
    gisn = malloc(i32[64])
    gmagg = malloc(i32[512])
    gmidx = malloc(i32[512])
    gmname = malloc(i32[512])
    gmcode = malloc(i32[512])
    gmarray = malloc(i32[512])
    gmdef = malloc(i32[512])
    gmdef2 = malloc(i32[512])
    gsel = malloc(i32[64])
    gdl = malloc(i32[16])
    gmsrc = malloc(i8[524288])
    gmtk = malloc(i32[1048576])
    gctname = malloc(i32[128])
    gct = malloc(i32[1024])
    gpenv = malloc(i32[16])
    gmbit = malloc(i32[512])
    gslice = malloc(i32[512])
    giname = malloc(i32[64])
    gis = malloc(i32[64])
    gie = malloc(i32[64])
    gmd = malloc(i32[48])
    gstate = malloc(i32[512])
    glastfrz = 0 - 1

    inp void = getenv("BOOT_IN")
    if inp == 0 {
        inp = "input.n0"
    }
    f void = fopen(inp, "r")
    if f == 0 {
        puts("boot2: cannot open input")
        return
    }
    gsrcn = fread(gsrc, 1, 524287, f)
    fclose(f)

    lex()
    lx void = getenv("BOOT_LEX")
    if lx != 0 {
        k i32 = 0
        while k < gntk {
            etk_dbg(k)
            k = k + 1
        }
        return
    }
    gntk = gntk
    gi = 0
    eo("#include <stdio.h>\n#include <stdint.h>\n#include <stddef.h>\n#include <stdlib.h>\n#include <string.h>\n\n")
    eo("static char* __nihao_strdup(const char* s) { size_t n = strlen(s) + 1; char* p = (char*)malloc(n); if (p != 0) memcpy(p, s, n); return p; }\n")
    eo("static void __nihao_init(void);\n\n")
    pre_aggs()
    emit_typedefs()
    eo("\n")
    emit_protos()
    eo("\n")
    gskipdefs = 1

    while ck() != 8 {
        top()
        eol()
    }

    /* 全局初始化函数 */
    eo("static void __nihao_init(void) { ")
    k9 i32 = 0
    while k9 < ginitn {
        a10 void = giname
        b10 void = gis
        c10 void = gie
        etk(a10.(i32[64])[k9])
        espace() ec(61) espace()
        p9 i32 = b10.(i32[64])[k9]
        while p9 < c10.(i32[64])[k9] {
            etk(p9)
            ec(32)
            p9 = p9 + 1
        }
        eo("; ")
        k9 = k9 + 1
    }
    eo("}\n")

    if gerr > 0 {
        print("错误: 共 %d 处诊断，未生成输出\n", gerr)
        return 1
    }

    outp void = getenv("BOOT_OUT")
    if outp == 0 {
        outp = "output.c"
    }
    o void = fopen(outp, "w")
    if o == 0 {
        puts("boot2: cannot create output")
        return
    }
    fwrite(gout, 1, goutn, o)
    fclose(o)
    print("boot2: %d bytes -> %s\n", goutn, outp)
}