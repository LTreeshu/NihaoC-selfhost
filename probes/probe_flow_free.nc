module main
use stdio

/* 探针：flow 自动释放（§11.1/§12.1，2026-11-28 实现，ncc ir-c 亦未实现此能力）
 * 预期产物：仅 b 退出 free（a 已转移、s 为字面量不释放）；运行输出 O / lit。
 * 把本文件喂给 boot2/boot3/boot4，grep 产物 free( 应恰 1 处。 */

func main() {
    flow a void = malloc(i8[8])
    a.(i8[8])[0] = 79
    a.(i8[8])[1] = 0
    flow b void = a
    puts(b)
    flow s void = "lit"
    puts(s)
}
