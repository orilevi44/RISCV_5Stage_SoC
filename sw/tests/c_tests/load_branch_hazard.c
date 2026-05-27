int main() {
    __asm__ volatile (
        "li x10, 0x1000 \n\t"
        "lw x11, 0(x10) \n\t"          // LOAD: קורא נתון מהזיכרון לאוגר x11
        "beq x11, x0, zero_label \n\t" // BRANCH: תלוי מיד בנתון של x11!
        
        "addi x12, x12, 1 \n\t"        // פקודת שווא 1
        "addi x13, x13, 1 \n\t"        // פקודת שווא 2
        
        "zero_label: \n\t"
        "add x14, x14, x14 \n\t"       // יעד הקפיצה
    );
    while(1);
    return 0;
}