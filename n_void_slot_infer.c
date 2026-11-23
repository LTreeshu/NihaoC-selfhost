#include <stdio.h>
#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>



typedef struct {int32_t x; int32_t y; } Pt;
int main() { int32_t x = 3;void* p = &x;(*((int32_t*)(p))) = 7;if (x == 7) { puts("void deref write ok");} else { puts("void deref write bad");}int32_t v = (*((int32_t*)(p)));if (v == 7) { puts("void deref read ok");} else { puts("void deref read bad");}if ((*((int64_t*)(p))) == 7) { puts("void empty subscript ok");} else { puts("void empty subscript bad");}(*((int64_t*)(p))) = 9;if (x == 9) { puts("void subscript write ok");} else { puts("void subscript write bad");}Pt pt = {0};void* q = &pt;q->x = 5;q->y = 6;q->x += 4;if (pt.x == 9 && pt.y == 6) { puts("void arrow ok");} else { puts("void arrow bad");}void* m = malloc(sizeof(int32_t));(*((int32_t*)(m))) = 11;if ((*((int32_t*)(m))) == 11) { puts("void malloc deref ok");} else { puts("void malloc deref bad");}int32_t arr[3] = {1, 2, 3};void* e = &arr;if ((*((int32_t*)(e))) == 1) { puts("void array elem ok");} else { puts("void array elem bad");}(*((int32_t*)(e))) = 8;if (arr[0] == 8) { puts("void array elem write ok");} else { puts("void array elem write bad");}return;return 0; }


