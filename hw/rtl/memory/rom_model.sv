`timescale 1ns / 1ps

// Instruction ROM — 4 KB (1024 × 32-bit words), base address 0x0000
module rom_model (
    input  logic [31:0] addr, // Address from CPU
    input  logic        en,   // Chip enable
    output logic [31:0] rd_data
);

    logic [31:0] mem [0:1023]; // 4KB ROM

    // אתחול הזיכרון - מתבצע פעם אחת בעת עליית המערכת (או צריבת ה-FPGA)
    initial begin
        // 1. קודם כל, נמלא את כל הזיכרון בפקודות NOP כדי להגן על הצנרת מ-X ומאפסים
        for (int i = 0; i < 1024; i++) begin
            mem[i] = 32'h00000013;
        end
        
        // 2. עכשיו נטען את קובץ התוכנה. 
        // פקודה זו תדרוס רק את הכתובות הראשונות שיש בקובץ, ותשאיר NOP בשאר!
        $readmemh("firmware.mem", mem);
    end

    // קריאה קומבינטורית: addr[11:2] משמיט את 2 הביטים התחתונים (Byte Alignment)
    assign rd_data = (en) ? mem[addr[11:2]] : 32'h00000013; // Return NOP if disabled

endmodule