/**
 * SoC Top-Level Testbench (Corrected Paths)
 */
`timescale 1ns / 1ps

module soc_tb();

    // --- 1. Simulation Signals ---
    logic clk;
    logic rst_n;
    logic [31:0] gpio_out;

    // --- 2. Instantiate the SoC (UUT) ---
    soc_top uut (
        .clk          (clk),
        .rst_n        (rst_n),
        .soc_gpio_out (gpio_out)
    );

    // --- 3. Clock Generation (100MHz) ---
    initial clk = 0;
    always #5 clk = ~clk;

    // --- 4. Main Simulation Control ---
    initial begin
        rst_n = 0;

        // Load the Program into ROM
        // Note: Using uut.u_rom.mem as seen in soc_top
        $readmemh("sim/program.hex", uut.u_rom.mem);
        $display("[TB] SoC ROM loaded successfully.");

        $dumpfile("sim/waves.fst");
        $dumpvars(0, soc_tb);

        repeat (5) @(posedge clk);
        #2 rst_n = 1; 
        $display("[TB] Reset released.");
        
        #10000;
        $display("[TIMEOUT] Simulation reached global limit.");
        $finish;
    end

    // --- 5. Continuous Debug Monitor (Advanced Debug Version) ---
    initial begin
        $display("\n[TIME]  |  PC  |  INSTR   | RS1_VAL | RS2_VAL |   IMM    | FwdA | FwdB | ALU_RES | Z | BTKN | FLUSH");
        $display("------------------------------------------------------------------------------------------------------------------");
        
        @(posedge rst_n); 
        
        forever @(negedge clk) begin
            $strobe("%7t | %h | %h | %h | %h | %h |  %b  |  %b  | %h | %b |  %b   |  %b", 
                $time,
                uut.u_core.if_pc,                // הכתובת הנוכחית
                uut.u_core.id_inst,              // הפקודה ב-Decode
                uut.u_core.id_read_data1,        // ערך גולמי מרגיסטר rs1
                uut.u_core.id_read_data2,        // ערך גולמי מרגיסטר rs2
                uut.u_core.id_imm,               // הערך המיידי (כאן נראה אם ה-Sign Extension תקין)
                uut.u_core.forward_a_sel,        // בחירת מקור אופרנד A (00=Reg, 01=WB, 10=MEM)
                uut.u_core.forward_b_sel,        // בחירת מקור אופרנד B
                uut.u_core.ex_alu_res,           // תוצאת החישוב
                uut.u_core.ex_alu_zero,          // דגל Zero
                uut.u_core.mem_branch_taken,     // האם הקפיצה אושרה
                uut.u_core.if_id_flush           // האם הצינור נוקה
            );
        end
    end

    // --- 6. End-of-Program Detection ---
    initial begin
        @(posedge rst_n);
        forever @(negedge clk) begin
            // Detect 'jal x0, 0' (0000006f)
            if (uut.u_core.id_inst == 32'h0000006f) begin
                $display("-----------------------------------------------------------------------");
                $display("[MONITOR] End loop detected at T=%t. Finishing...", $time);
                repeat (10) @(negedge clk); 
                $display("SIMULATION COMPLETE");
                $display("Final GPIO state: %h", gpio_out);
                $display("-----------------------------------------------------------------------");
                $finish;
            end
        end
    end

    initial begin
        forever @(negedge clk) begin
            if (uut.u_core.if_pc === 32'hx || uut.u_core.if_pc === 32'hz) begin
                $display("\n[!!!] X-PROPAGATION DETECTED AT T=%t", $time);
                $display("[!!!] Stopping simulation to prevent log flooding.");
                $finish;
            end
        end
    end

endmodule