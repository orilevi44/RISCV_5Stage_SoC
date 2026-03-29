`timescale 1ns / 1ps

module reg_file (
    input  logic        clk,
    input  logic        we,             // Write Enable (מגיע משלב ה-WB)
    input  logic [4:0]  read_reg1,      // rs1
    input  logic [4:0]  read_reg2,      // rs2
    input  logic [4:0]  write_reg,     // rd
    input  logic [31:0] write_data,     // המידע לכתיבה
    output logic [31:0] read_data1,
    output logic [31:0] read_data2
);

    logic [31:0] registers [31:0];

    // אתחול רגיסטרים לאפס
    initial begin
        for (int i = 0; i < 32; i++) registers[i] = 32'b0;
    end

    /**
     * Internal Forwarding (Bypass Logic):
     * אם אנחנו קוראים מרגיסטר בדיוק כשהוא נכתב (באותו מחזור שעון),
     * אנחנו מושכים את המידע ישירות מה-write_data במקום מהמערך הישן.
     */
    assign read_data1 = (read_reg1 == 5'b0) ? 32'b0 : 
                        ((we && (read_reg1 == write_reg)) ? write_data : registers[read_reg1]);
                        
    assign read_data2 = (read_reg2 == 5'b0) ? 32'b0 : 
                        ((we && (read_reg2 == write_reg)) ? write_data : registers[read_reg2]);

    // כתיבה מסונכרנת לשעון
    always_ff @(posedge clk) begin
        if (we && (write_reg != 5'b0)) begin
            registers[write_reg] <= write_data;
        end
    end
endmodule