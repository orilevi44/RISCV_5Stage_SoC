.section .text.init
.global _start

_start:
    /* הגדרת מצביע המחסנית (Stack Pointer) לקצה העליון של ה-RAM - כתובת 0x3000 */
    li sp, 0x3000      
    
    /* קפיצה לפונקציה הראשית ב-C */
    call main          

end_loop:
    /* תפיסת המעבד בלולאה אינסופית אם בטעות יצאנו מה-main */
    j end_loop

    