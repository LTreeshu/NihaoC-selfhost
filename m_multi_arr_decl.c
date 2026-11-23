#include <stdio.h>
#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>



int main() { char aa[3] = "aa" ; char bb[3] = "bb" ; char cc[3] = "cc" ; if ((int64_t)(sizeof(aa)/sizeof(aa[0])) == 3) { puts("cap3 ok");}puts(aa);puts(cc);char* d1 = "abcd" ; char* d2 = "xy" ; if ((int64_t)strlen(d1) == 4) { puts("dyn4 ok");}if ((int64_t)strlen(d2) == 2) { puts("dyn2 ok");}puts(d1);int8_t a = 0 ; int8_t b = 1 ; int8_t c = 0 ; if (a == 0 && b == 1 && c == 0) { puts("scalar ok");}puts("multi arr decl ok");return 0; }


