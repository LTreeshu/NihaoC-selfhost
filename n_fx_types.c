#include <stdio.h>
#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>


void add32(int64_t a, int64_t b) { return a + b;}

void wide64(int64_t a, int64_t b) { return a + b;}

int main() { x;fx32 = 7;y;fx32 = 3;if (x + y == 10) { puts("fx32 add ok");} else { puts("fx32 add bad");}if (x - y == 4) { puts("fx32 sub ok");} else { puts("fx32 sub bad");}if (x * y == 21) { puts("fx32 mul ok");} else { puts("fx32 mul bad");}if (x / y == 2) { puts("fx32 div ok");} else { puts("fx32 div bad");}t;fx32 = 5000000000;if (t == 705032704) { puts("fx32 decl trunc ok");} else { puts("fx32 decl trunc bad");}s;fx32 = 0;s = 5000000000;if (s == 705032704) { puts("fx32 assign trunc ok");} else { puts("fx32 assign trunc bad");}u;fx64 = 5000000000;if (u == 5000000000) { puts("fx64 wide ok");} else { puts("fx64 wide bad");}if (sizeof(int64_t)) { fx32;0 == 4;{ puts("fx32 size ok");}int64_t puts = 0; sizeof(int64_t);fx64;0 == 8;{ puts("fx64 size ok");}int64_t puts = 0; i32 = 5;if (i + x == 12) { puts("fx int mix ok");} else { puts("fx int mix bad");}if (add32(x, y) == 10) { puts("fx32 call ok");} else { puts("fx32 call bad");}if (wide64(u, 1) == 5000000001) { puts("fx64 call ok");} else { puts("fx64 call bad");}}return 0; }

