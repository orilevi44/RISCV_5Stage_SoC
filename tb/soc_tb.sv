`timescale 1ns / 1ps

module soc_tb();
    // --- 1. Signals ---
    logic clk, rst_n, uart_tx;
    logic [31:0] gpio_out;

    // --- 2. Instantiate SoC ---
    soc_top uut (
        .clk(clk), .rst_n(rst_n), 
        .soc_gpio_out(gpio_out), .soc_uart_tx(uart_tx)
    );

    // --- 3. Clock & Reset Generation ---
    initial begin clk = 0; forever #5 clk = ~clk; end
    initial begin
        rst_n = 0;
        // מילוי הזיכרון ב-NOP
        for (int i = 0; i < 1024; i++) uut.u_rom.mem[i] = 32'h00000013;
        $readmemh("sim/program.hex", uut.u_rom.mem);
        repeat (10) @(posedge clk);
        #2 rst_n = 1;
        $display("\n[TB] Reset released. Starting execution...");
    end

    // --- 4. Hierarchical Spying ---
    logic        spy_uart_we;
    logic        spy_uart_sel;
    logic [31:0] spy_bus_wdata;

    assign spy_uart_we   = uut.uart_we;
    assign spy_uart_sel  = uut.uart_sel;
    assign spy_bus_wdata = uut.data_wdata;

    // --- 5. UART Collector (הגרסה היציבה ללא String) ---
    logic [7:0] char_history [0:15]; // מערך לשמירת עד 16 תווים
    int char_count = 0;
    
    initial begin
        for (int i = 0; i < 16; i++) char_history[i] = 8'h00;
        
        forever @(posedge clk) begin
            if (rst_n) begin
                // בכל פעם שיש כתיבה ל-UART
                if (spy_uart_we && spy_uart_sel) begin
                    if (char_count < 16) begin
                        char_history[char_count] = spy_bus_wdata[7:0];
                        char_count = char_count + 1;
                    end
                    // הדפסה מיידית לטרמינל (ללא אגירה)
                    $write("%c", spy_bus_wdata[7:0]);
                end

                
                // זיהוי סיום תוכנית (Parking)
                if (uut.u_core.actual_jump && (uut.u_core.final_branch_addr == (uut.u_core.ex_pc - 4))) begin
                    $display("\n\n**************************************************");
                    $display("      DEEP HARDWARE TEST SUMMARY");
                    $display("**************************************************");
                    $write("  CPU Sent: ");
                    for (int i = 0; i < char_count; i++) $write("%c", char_history[i]);
                    $display("");
                    $display("--------------------------------------------------");
                    
                    // בדיקה האם התווים שנתפסו הם "YES"
                    if (char_count >= 3 && char_history[0] == 8'h59 && char_history[1] == 8'h45 && char_history[2] == 8'h53) begin
                        $display("  RESULT: [PASS] - Logic is perfect! CPU says YES! 🎉");
                    end else if (char_count >= 2 && char_history[0] == 8'h4e && char_history[1] == 8'h4f) begin
                        $display("  RESULT: [FAIL] - Calculation/RAM error. CPU says NO.");
                    end else begin
                        $display("  RESULT: [FAIL] - Unexpected response format.");
                    end
                    
                    $display("**************************************************\n");
                    $finish;
                end
            end
        end
    end

    // טיימר הגנה למקרה שהתוכנית נתקעת
    initial begin #2000000; $display("\n[TIMEOUT]"); $finish; end

endmodule