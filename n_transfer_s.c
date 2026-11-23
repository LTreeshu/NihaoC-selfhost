#include <stdio.h>
#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>



void* p = malloc(sizeof(int32_t));
int main() {
 void* x = create();
printf("%lld\n", (long long)((*((int32_t*)(x)))));
puts("transfer ok");
return 0;

}



