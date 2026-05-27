`timescale 1ns/1ns

module tb_icache();

    logic        clk;
    logic        rst_n;
    
    // CPU Interface
    logic [31:0] cpu_pc;
    logic [31:0] cpu_inst;
    logic        cpu_stall;
    
    // ROM Interface
    logic [31:0] rom_data;
    logic [31:0] rom_pc;
    logic        rom_read_en;

    // 2. יצירת מופע של ה-Cache
    icache uut (
        .clk(clk),
        .rst_n(rst_n),
        .cpu_pc(cpu_pc),
        .cpu_inst(cpu_inst),
        .cpu_stall(cpu_stall),
        .rom_data(rom_data),
        .rom_pc(rom_pc),
        .rom_read_en(rom_read_en)
    );

    // 3. מחולל השעון (Clock Generator)
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // מחזור שעון של 10ns
    end

    // 4. סימולציה של זיכרון ROM (תגובה עם Latency = 1)
    always_ff @(posedge clk) begin
        if (rom_read_en) begin
            // לשם הפשטות בטסט, נחזיר פשוט את הכתובת בתור הנתון
            // ככה נוכל לראות בקלות שה-Cache מביא את המידע הנכון
            rom_data <= rom_pc; 
        end
    end

    // 5. תסריט הבדיקה (Test Scenario)
    initial begin
        // אתחול המערכת
        rst_n = 0;
        cpu_pc = 32'b0;
        
        // המתנה של כמה מחזורי שעון לשחרור הריסט
        #20;
        rst_n = 1;

        // --- ניסוי 1: Cache Miss ---
        $display("[%0t] TEST 1: Requesting Address 0x00000008", $time);
        cpu_pc = 32'h00000008; 
        
        // נחכה עד שה-Stall יירד (כלומר, ה-Cache סיים להביא נתונים מה-ROM)
        wait(cpu_stall == 1'b0);
        #1; // המתנה קטנה כדי לראות את הערך בגל
        
        $display("[%0t] HIT! CPU received instruction: 0x%08h", $time, cpu_inst);
        if (cpu_inst == 32'h00000008) $display("-> SUCCESS: Instruction matches requested PC.");
        else $display("-> ERROR: Mismatch!");

        // נחכה מחזור שעון אחד
        #10;

        // --- ניסוי 2: Cache Hit (Spatial Locality) ---
        $display("[%0t] TEST 2: Requesting Address 0x0000000C", $time);
        cpu_pc = 32'h0000000C;
        
        #1; // ניתן לחומרה הקומבינטורית להתעדכן
        if (cpu_stall == 1'b0) begin
             $display("[%0t] INSTANT HIT! CPU received instruction: 0x%08h", $time, cpu_inst);
             if (cpu_inst == 32'h0000000C) $display("-> SUCCESS: Instruction matches requested PC.");
             else $display("-> ERROR: Mismatch!");
        end else begin
             $display("[%0t] ERROR: Expected an instant hit, but got a stall!", $time);
        end

        // סיום הסימולציה
        #50;
        $display("Simulation Finished.");
    $finish;
    end
endmodule