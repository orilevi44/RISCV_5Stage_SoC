// מיפוי הכתובת הפיזית של רכיב ה-GPIO בזיכרון
#define GPIO_OUT *((volatile unsigned int*)0x1000)

int main() {
    int a = 0;
    int b = 1;
    int c;

    // הצגת המספר הראשון בסדרה
    GPIO_OUT = a;

    while(1) {
        // חישוב האיבר הבא בסדרת פיבונאצ'י
        c = a + b;
        a = b;
        b = c;

        // כתיבת התוצאה אל ה-GPIO (הדלקת הלדים)
        GPIO_OUT = a;

        // איפוס הסדרה לפני גלישה מ-16 ביט
        if (a > 40000) {
            a = 0;
            b = 1;
        }

        // השהיה קצרצרה המותאמת במיוחד לסימולציה מהירה
        for(volatile int delay = 0; delay < 5; delay++) {
            // המתנה פעילה
        }
    }

    return 0;
}