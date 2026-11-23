#include <stdio.h>
#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>


int main() {
 int32_t x = 42;
int32_t*p = &x;
int32_t y = (*((int32_t*)(p)));
if (y == 42) {
 puts("ptr read ok");

}
 else {
 puts("ptr read bad");

}
(*((int32_t*)(p))) = 43;
if (x == 43) {
 puts("ptr write ok");

}
 else {
 puts("ptr write bad");

}
double d = 3.5;
double*pd = &d;
double z = (*((double*)(pd)));
if (z == 3.5) {
 puts("ptr double ok");

}
 else {
 puts("ptr double bad");

}
int8_t c = 100;
int8_t*pc = &c;
(*((int8_t*)(pc))) = 300;
if (c == 44) {
 puts("ptr narrow ok");

}
 else {
 puts("ptr narrow bad");

}
q = p + 1;
puts("ptr arith ok");
(*((int32_t*)(p))) += 2;
if (x == 45) {
 puts("ptr compound ok");

}
 else {
 puts("ptr compound bad");

}
(*((double*)(pd))) += 1.0;
z = (*((double*)(pd)));
if (z == 4.5) {
 puts("ptr double compound ok");

}
 else {
 puts("ptr double compound bad");

}
(*((int8_t*)(pc))) += 1;
if (c == 45) {
 puts("ptr narrow compound ok");

}
 else {
 puts("ptr narrow compound bad");

}
(*((int32_t*)(p))) *= 3;
if (x == 135) {
 puts("ptr mul ok");

}
 else {
 puts("ptr mul bad");

}
(*((int32_t*)(p))) -= 10;
if (x == 125) {
 puts("ptr sub ok");

}
 else {
 puts("ptr sub bad");

}
return;
return 0;

}



