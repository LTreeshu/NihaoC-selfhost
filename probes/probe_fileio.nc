module main
use stdio

/* 探针：文件读写（fopen/fread/fwrite/fclose 走外部符号路径） */

func main() {
    src void = malloc(i8[4096])
    f void = fopen("probe_in.txt", "r")
    if f == 0 {
        puts("open failed")
        return
    }
    n i32 = fread(src, 1, 4095, f)
    fclose(f)
    print("read=%d\n", n)

    o void = fopen("probe_out.txt", "w")
    if o == 0 {
        puts("create failed")
        return
    }
    fwrite(src, 1, n, o)
    fclose(o)
    puts("fileio ok")
}
