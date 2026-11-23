#include <stdio.h>
#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>



int main() { int32_t arr[6] = {10, 20, 30, 40, 50, 60};if ((int64_t)(sizeof(arr)/sizeof(arr[0])) == 6) { puts("len array ok");} else { puts("len array bad");}int32_t m[2][3] = {{1, 2, 3}, {4, 5, 6}};if ((int64_t)(sizeof(m)/sizeof(m[0][0])) == 6) { puts("len multidim ok");} else { puts("len multidim bad");}char* d = "hello";if ((int64_t)strlen(d) == 5) { puts("len dynstr ok");} else { puts("len dynstr bad");}char* s = "abc";if ((int64_t)strlen(s) == 3) { puts("len strlit ok");} else { puts("len strlit bad");}int32_t*sl = (&(arr[1]));if (3 == 3 && (*((int32_t*)(sl))) == 20) { puts("len slice ok");} else { puts("len slice bad");}int32_t*sw = (&(arr[0]));if (5 == 5) { puts("len slice open ok");} else { puts("len slice open bad");}int32_t cp[3]; memcpy(cp, (arr) + (1), sizeof(cp));if ((int64_t)(sizeof(cp)/sizeof(cp[0])) == 3 && cp[2] == 40) { puts("len sliced copy ok");} else { puts("len sliced copy bad");}if ((int64_t)(sizeof(arr)/sizeof(arr[0])) == 6) { puts("len stable ok");} else { puts("len stable bad");}return;return 0; }


