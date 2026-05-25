
#include <stdint.h>

#define GPIO_ADDR 0x1000
#define GPIO_REG *((volatile uint32_t*)GPIO_ADDR)


int main(){
    int a = 5; 
    int b = 6; 
    int x;
    x = a + b ; 

    GPIO_REG = x ;

    while(1);
    return 0 ;
}