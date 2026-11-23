#include <stdio.h>
#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>



typedef enum {
LOW = 1, MID = 5, HIGH = 9
}
 Level;
int32_t pick(int32_t v, int32_t want) {
 int32_t hit = 0;
int32_t n = v;
while (1) {
 int64_t __is1 = (n);
if (!__is1) break;
{
 if (__is1 == -3) {
 hit = 1;
break;

}
if (__is1 == 0) {
 5;
{
 hit = 2;
break;

}
if (__is1 == -9) {
 0 - 5;
{
 hit = 3;
break;

}
if (__is1 == LOW) {
 hit = 4;
break;

}
if (__is1 == want) {
 hit = 5;
break;

}
if (__is1 || 1) {
 hit = 6;
break;

}

}
return hit;

}
func;
main();
{
 if (pick(-3, 7) == 1) {
 puts("is negative lit ok");

}
 else {
 puts("is negative lit bad");

}
if (pick(5, 7) == 2) {
 puts("is signed lit ok");

}
 else {
 puts("is signed lit bad");

}
if (pick(-7, 7) == 3) {
 puts("is negative range ok");

}
 else {
 puts("is negative range bad");

}
if (pick(1, 7) == 4) {
 puts("is enum variant ok");

}
 else {
 puts("is enum variant bad");

}
if (pick(7, 7) == 5) {
 puts("is ident by value ok");

}
 else {
 puts("is ident by value bad");

}
if (pick(4, 7) == 6) {
 puts("is wildcard ok");

}
 else {
 puts("is wildcard bad");

}
if (pick(5, 5) == 2) {
 puts("is first match only ok");

}
 else {
 puts("is first match only bad");

}
return;

}

}
 
}

}


