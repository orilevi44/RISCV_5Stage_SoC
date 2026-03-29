module timer (
    input  logic        clk,
    input  logic        rst_n,

    // --- Bus Interface ---
    input  logic [31:0] bus_addr,       // The address from the CPU
    input  logic [31:0] bus_write_data, // Data to write to the timer
    input  logic        bus_write_en,   // Write enable signal
    input  logic        bus_read_en,    // Read enable signal
    output logic [31:0] bus_read_data,  // Data requested by the CPU

    // --- Interrupt Signal ---
    output logic        timer_irq       // Goes high when timer matches and IRQ is enabled
);

    // ==========================================
    // 0. Icarus Verilog Workaround (Offset Wire)
    // ==========================================
    // Extracting the bottom 4 bits OUTSIDE the always_comb block 
    // to prevent compiler "constant select" errors.
    logic [3:0] timer_offset;
    assign timer_offset = bus_addr[3:0];

    // ==========================================
    // 1. Internal Registers
    // ==========================================
    logic [31:0] timer_val;  // Offset 0x0
    logic [31:0] timer_cmp;  // Offset 0x4
    
    // CTRL Register fields (Offset 0x8)
    logic timer_en;          // Bit 0: Enable the counter
    logic match_flag;        // Bit 1: Goes high when val == cmp
    logic irq_en;            // Bit 2: Allow interrupts

    // ==========================================
    // 2. Write Logic & Counting Mechanism
    // ==========================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            timer_val  <= 32'b0;
            timer_cmp  <= 32'hFFFFFFFF; // Default to max value
            timer_en   <= 1'b0;
            match_flag <= 1'b0;
            irq_en     <= 1'b0;
        end else begin
            // PRIORITY 1: CPU Write Operation
            // If the CPU wants to write, it overwrites whatever the timer is doing
            if (bus_write_en) begin
                // Using our safe wire here too for consistency
                case (timer_offset)
                    4'h0: timer_val <= bus_write_data;
                    4'h4: timer_cmp <= bus_write_data;
                    4'h8: begin
                        timer_en   <= bus_write_data[0];
                        match_flag <= bus_write_data[1]; // CPU writes 0 to clear the flag
                        irq_en     <= bus_write_data[2];
                    end
                endcase
            end
            
            // PRIORITY 2: Hardware Counting
            // If the CPU isn't writing AND the timer is enabled
            else if (timer_en) begin
                if (timer_val >= timer_cmp) begin
                    match_flag <= 1'b1;  // Raise the flag!
                    timer_val  <= 32'b0; // Auto-reload to 0
                end else begin
                    timer_val <= timer_val + 1'b1; // Increment counter
                end
            end
        end
    end

    // ==========================================
    // 3. Read Logic
    // ==========================================
    always_comb begin
        bus_read_data = 32'b0; // Default

        if (bus_read_en) begin
            // NO MORE COMPILER ERRORS: Using the clean 4-bit wire instead of bus_addr[3:0]
            case (timer_offset)
                4'h0: bus_read_data = timer_val;
                4'h4: bus_read_data = timer_cmp;
                // Construct the CTRL register from its individual bits
                4'h8: bus_read_data = {29'b0, irq_en, match_flag, timer_en};
                default: bus_read_data = 32'b0;
            endcase
        end
    end

    // ==========================================
    // 4. Interrupt Generation
    // ==========================================
    // The alarm sounds ONLY if the flag is raised AND the CPU allowed interrupts
    assign timer_irq = match_flag & irq_en;

endmodule