#include<stdint.h>

#define GPIO_ADDR 0x1000
#define GPIO_REG *((volatile uint32_t*)GPIO_ADDR)

int main() {
    volatile uint32_t result = 0;

    // test 1 : basic alu test -> add , sub , shifts 
    uint32_t a = 15;
    uint32_t b = 5;
    result = (a + b) - (a>>1) ; // 20 - 7 = 13 

    GPIO_REG = result ; //first check: in the simulation is should show 13 on the GPIO 

    // test 2 : 
    volatile uint32_t mem_array[4];
    mem_array[0] = 0xAABBCCDD; 
    result = mem_array[0]; 

    // test 3: 
    volatile uint8_t* byte_ptr = (volatile uint8_t*)&mem_array[1];
    byte_ptr[0] = 0x11; 
    byte_ptr[1] = 0x22; 
    byte_ptr[2] = 0x33;
    byte_ptr[3] = 0x44; 

    result = mem_array[1];
    GPIO_REG = result; 
    
    
    // test 4 : 
    int count = 0 ; 
    for (int i = 0 ; i < 5 ; i++ ) { 
        count += 1; 
    }

    if (count < 10){ 
        GPIO_REG =0xFF ; 
    }
    else  {
        GPIO_REG = 0xEE ; 
    }

    while(1);
    return 0 ;
}