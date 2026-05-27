int main(){ 

    __asm__ volatile ( 

        "li x15 , 100 \n\t"
        "li x15 , 200 \n\t"
        "addi x16,x15,0 \n\t"
    ); 
    
    while(1); 
    return 0;
}