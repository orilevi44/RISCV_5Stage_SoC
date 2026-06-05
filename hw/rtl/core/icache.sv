`timescale 1ns/1ns

/**
 * ============================================================================
 * Module      : icache
 * Description : 32-bit Direct-Mapped Instruction Cache for RISC-V Core.
 * Features a 4-word block size (128 bits per line) and 8 cache 
 * lines. Includes safety latches to prevent address corruption
 * during speculative branch flushes while fetching.
 * ============================================================================
 */
module icache (
    input  logic        clk,
    input  logic        rst_n,

    // --------------------------------------------------
    // CPU Interface (Fetch Stage)
    // --------------------------------------------------
    input  logic [31:0] cpu_pc,       // Program Counter from the CPU
    output logic [31:0] cpu_inst,     // 32-bit Instruction routed back to CPU
    output logic        cpu_stall,    // Freezes the pipeline on an I-Cache miss

    // --------------------------------------------------
    // ROM / Main Memory Interface
    // --------------------------------------------------
    input  logic [31:0] rom_data,     // Data read from ROM
    output logic [31:0] rom_pc,       // Address requested from ROM
    output logic        rom_read_en   // Read enable signal for ROM
);

    // ==================================================
    // Parameters & Data Structures
    // ==================================================
    localparam TAG_BITS    = 25; // 32 - 4 (offset) - 3 (index) = 25 bits
    localparam INDEX_BITS  = 3;  // 2^3 = 8 cache lines
    localparam OFFSET_BITS = 4;  // 16 bytes per line = 4 words
    localparam CACHE_DEPTH = 8;

    // Structure defining a single cache line
    typedef struct packed {
        logic                valid; // 1 = contains valid instruction data
        logic [TAG_BITS-1:0] tag;   // Address tag to identify the memory block
        logic [127:0]        data;  // 4 words (16 Bytes = 128 bits) payload
    } cache_line_t;

    // The actual cache memory array
    cache_line_t cache_mem [0:CACHE_DEPTH-1];
    
    // ==================================================
    // Internal Signals & Address Decoding
    // ==================================================
    logic [24:0] req_tag;
    logic [2:0]  req_index;
    logic [3:0]  req_offset;

    // Decode the incoming CPU PC
    assign req_tag    = cpu_pc[31:7];
    assign req_index  = cpu_pc[6:4];
    assign req_offset = cpu_pc[3:0];

    cache_line_t current_line; 
    assign current_line = cache_mem[req_index]; 

    // Hit detection: Line must be valid and tags must match
    logic cache_hit; 
    assign cache_hit = (current_line.valid == 1'b1) && (current_line.tag == req_tag); 

    // Stall the CPU pipeline immediately if the instruction is not cached
    assign cpu_stall = !cache_hit;

    // ==================================================
    // Combinational: CPU Read Routing
    // ==================================================
    always_comb begin
        // Default assignment: Inject a safe NOP (addi x0, x0, 0) during misses
        // to prevent downstream pipeline errors and avoid inferred latches.
        cpu_inst = 32'h00000013; 

        if (cache_hit) begin
            // Route the correct 32-bit word from the 128-bit cache line based on the offset
            case(req_offset[3:2]) 
                2'b00: cpu_inst = current_line.data[31:0]; 
                2'b01: cpu_inst = current_line.data[63:32];
                2'b10: cpu_inst = current_line.data[95:64]; 
                2'b11: cpu_inst = current_line.data[127:96]; 
            endcase
        end
    end

    // ==================================================
    // FSM State Definitions
    // ==================================================
    typedef enum logic [1:0] { 
        COMPARE,  // Check for hit/miss. Serve data if hit.
        FETCH,    // Pull 4 sequential words from the ROM.
        ALLOCATE  // Write the assembled 128-bit block into the cache memory.
     } my_state_type_t;

     my_state_type_t state, next_state; 
     logic [2:0]   fetch_counter;
     logic [127:0] line_buffer;

     // ----------------------------------------------------
     // Safety Latches (Address Corruption Prevention)
     // ----------------------------------------------------
     // These registers latch the target address at the exact moment a miss occurs.
     // This prevents the I-Cache from fetching mixed blocks or writing to the wrong 
     // index if the CPU pipeline executes a speculative jump mid-fetch.
     logic [31:0] fetch_base_addr;
     logic [24:0] latched_tag;
     logic [2:0]  latched_index;

    // ==================================================
    // FSM Combinational Logic
    // ==================================================
     always_comb begin
        next_state = state; 
        case(state) 
            COMPARE: begin 
                if (cache_hit) begin
                    next_state = COMPARE; 
                end else begin
                    next_state = FETCH;
                end
            end
            FETCH: begin
                // Transition to ALLOCATE only after 4 data beats have been successfully read
                if (fetch_counter == 3'd5) begin 
                    next_state = ALLOCATE; 
                end else begin
                    next_state = FETCH; 
                end
            end
            ALLOCATE: begin 
                next_state = COMPARE; 
            end
            default: next_state = COMPARE; 
        endcase
    end
    
    // ==================================================
    // FSM Sequential Logic
    // ==================================================
    integer i; 

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset cache validity
            for (i = 0; i < CACHE_DEPTH; i++) begin
                cache_mem[i].valid <= 1'b0;
            end
            state           <= COMPARE;
            fetch_counter   <= 3'b0;
            
            // Clear safety latches
            fetch_base_addr <= 32'b0;
            latched_tag     <= 25'b0;
            latched_index   <= 3'b0;
        end else begin
            state <= next_state; 

            case(state)

                COMPARE: begin 
                    if (!cache_hit) begin 
                        fetch_counter <= 3'b0; 
                        
                        // Latch the PC components immediately upon detecting a miss!
                        // Strip the offset to align to the 16-byte block boundary.
                        fetch_base_addr <= {cpu_pc[31:4], 4'b0000};
                        latched_tag     <= req_tag;
                        latched_index   <= req_index;
                    end
                end

                FETCH: begin 
                    // --- ROM Request Manager ---
                    if (fetch_counter <= 3'd3) begin
                        rom_read_en <= 1'b1; 
                        // Fetch sequentially using the LATCHED base address, ignoring the live CPU PC
                        rom_pc <= fetch_base_addr + (4 * fetch_counter);
                    end else begin
                        rom_read_en <= 1'b0; 
                    end

                    // --- ROM Response Manager ---
                    // Capture incoming data into the 128-bit assembly buffer
                    if (fetch_counter >= 3'd1 && fetch_counter <= 3'd4) begin 
                        line_buffer[(fetch_counter-1) * 32 +: 32] <= rom_data; 
                    end
                    
                    // --- Counter Manager ---
                    if (fetch_counter == 3'd5) begin
                        fetch_counter <= 3'd0; 
                    end else begin
                        fetch_counter <= fetch_counter + 1'd1;
                    end
                end

                ALLOCATE: begin
                    // Write the fully assembled block into the cache array.
                    // CRITICAL: Use the latched index and tag, not the live decoded signals.
                    cache_mem[latched_index] <= '{valid: 1'b1, tag: latched_tag, data: line_buffer}; 
                end

            endcase
        end
    end
endmodule