int main() { 

    __asm__ volatile ( 
        "li x1 , 5 \n\t"
        "li x2 , 6 \n\t"
        "beq x1 ,x2,target \n\t"

        "target: \n\t" 
        "jal target \n\t"
    ); 

    while(1); 
    return 0;
}