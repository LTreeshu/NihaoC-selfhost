#include <stdio.h>
#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>


int main() { int32_t a = 1 ; int32_t b = 2 ; int32_t c = 3 ; if (a == 1 && b == 2 && c == 3) { puts("multi ok");} else { puts("multi bad");}a = 10;if (a == 10 && b == 2) { puts("multi write ok");} else { puts("multi write bad");}const int32_t MIN = 0 ; const int32_t MAX = 100 ; if (MAX == 100 && 1 == 1) { puts("const multi ok");} else { puts("const multi bad");}int32_t x = 5;int32_t p = x + 1 ; int32_t q = x * 2 ; if (p == 6 && q == 10) { puts("expr init ok");} else { puts("expr init bad");}return;return 0; }


