`timescale 1ns/1ns


module icache (
    input logic clk,
    input logic rst_n,

    //cpu interface
    input logic [31:0]  cpu_pc, 
    output logic [31:0] cpu_inst,
    output logic        cpu_stall, 

    //rom interface 
    input logic [31:0]  rom_data,
    output logic [31:0] rom_pc,
    output logic        rom_read_en // tell the rom i want to read 
);
    //cache parametrs
    localparam TAG_BITS = 25 ;
    localparam INDEX_BITS = 3 ;
    localparam OFFSET_BITS = 4 ;
    localparam CACHE_DEPTH = 8; // 2^INDEX_BITS

    // cache line srtucture

    typedef struct packed {
        logic                valid;
        logic [TAG_BITS-1:0] tag;
        logic [127:0]        data;  // 16 Bytes = 128 bits 
    } cache_line_t;

    cache_line_t cache_mem [0:7];
    
    logic [24:0] req_tag;
    logic [2:0] req_index;
    logic [3:0] req_offset ;

    assign req_tag    = cpu_pc[31:7];
    assign req_index  = cpu_pc[6:4];
    assign req_offset = cpu_pc[3:0];

    cache_line_t current_line ; 
    assign current_line = cache_mem[req_index]; 


    logic cache_hit; 
    assign cache_hit = ((current_line.valid == 1'b1)&&(current_line.tag == req_tag)); 

    assign cpu_stall = (cache_hit)? 1'b0 :1'b1;

    always_comb begin

        // Default assignment to prevent inferred latches
        cpu_inst = 32'h00000013; // Inject NOP on a miss

        if (cache_hit) begin
            case(req_offset[3:2]) 
                2'b00: cpu_inst = current_line.data[31:0]; 
                2'b01: cpu_inst = current_line.data[63:32];
                2'b10: cpu_inst = current_line.data[95:64]; 
                2'b11: cpu_inst = current_line.data[127:96]; 
            endcase
        end

    end

    typedef enum logic [1:0] { 
        COMPARE, // hit or miss
        FETCH,  // bring 4 words from the ROM 
        ALLOCATE // write a full line to the cache 
     } my_state_type_t;

     my_state_type_t state , next_state; 
     logic [2:0] fetch_counter;
     logic [127:0] line_buffer;


     always_comb begin

        next_state = state; 
        case(state) 
        COMPARE: begin 
            if(cache_hit) begin
                next_state = COMPARE; 
            end else begin
                next_state = FETCH;
            end
        end
        FETCH: begin
            if (fetch_counter == 3'd5) begin 
                    next_state = ALLOCATE; 
            end 
            else next_state = FETCH; 
        end
        ALLOCATE:begin 
            next_state = COMPARE; 
        end
        default: next_state = COMPARE; 
        endcase
    end
    
    integer i ; 

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 8; i++) begin
                cache_mem[i].valid <= 1'b0;
            end
            state         <= COMPARE;
            fetch_counter <= 2'b00;
        end else begin
            state <= next_state; 

            case(state)

            COMPARE:begin 
                if(!cache_hit)begin 
                fetch_counter <= 0 ; 
                end
            end

            FETCH:begin 
                // request manager 
                if (fetch_counter <= 3'd3) begin
                    rom_read_en <= 1'b1; 
                    rom_pc <= {cpu_pc[31:4] , 4'b0000} + (4*fetch_counter);
                end else begin
                    rom_read_en <= 1'b0; 
                end

                //response manager
                if (fetch_counter >= 3'd1 && fetch_counter <= 3'd4) begin 
                    line_buffer[(fetch_counter-1) * 32 +: 32] <= rom_data ; 
                end
                
                //counter manager
                if (fetch_counter == 3'd5) begin
                    fetch_counter <= 3'd0; 
                end else begin
                    fetch_counter <= fetch_counter + 1'd1;
                end
            end

            ALLOCATE:begin
                cache_mem[req_index] <= '{valid: 1'b1,tag: req_tag,data:line_buffer}; // vaild,tag ,data 
            end

            endcase
        end
    end
endmodule