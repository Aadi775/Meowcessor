// Load/store lane steering for a 32-bit little-endian data-memory bus.
// The memory returns the aligned 32-bit word containing effective_addr.
module lsu #(
    parameter WIDTH = 32
)(
    input  wire [WIDTH-1:0] effective_addr,
    input  wire [2:0]       funct3,
    input  wire [WIDTH-1:0] store_data,
    input  wire [WIDTH-1:0] memory_rdata,
    output wire [WIDTH-1:0] memory_addr,
    output wire [WIDTH-1:0] memory_wdata,
    output reg  [3:0]       memory_wstrb,
    output reg  [WIDTH-1:0] load_data
);

    wire [1:0] byte_offset = effective_addr[1:0];
    wire [4:0] shift_amount = {byte_offset, 3'b000};
    wire [WIDTH-1:0] shifted_store = store_data << shift_amount;
    wire [WIDTH-1:0] shifted_load = memory_rdata >> shift_amount;

    // Keep the effective byte address externally visible. The memory model or
    // interconnect aligns it to a word; the low bits select the byte lanes.
    assign memory_addr = effective_addr;
    assign memory_wdata = shifted_store;

    always @(*) begin
        memory_wstrb = 4'b0000;
        load_data = {WIDTH{1'b0}};

        case (funct3)
            3'b000: begin // LB / SB
                memory_wstrb = 4'b0001 << byte_offset;
                load_data = {{(WIDTH-8){shifted_load[7]}}, shifted_load[7:0]};
            end
            3'b100: begin // LBU
                load_data = {{(WIDTH-8){1'b0}}, shifted_load[7:0]};
            end
            3'b001: begin // LH / SH
                memory_wstrb = 4'b0011 << byte_offset;
                load_data = {{(WIDTH-16){shifted_load[15]}}, shifted_load[15:0]};
            end
            3'b101: begin // LHU
                load_data = {{(WIDTH-16){1'b0}}, shifted_load[15:0]};
            end
            3'b010: begin // LW / SW
                memory_wstrb = 4'b1111;
                load_data = memory_rdata;
            end
            default: begin
                memory_wstrb = 4'b0000;
                load_data = {WIDTH{1'b0}};
            end
        endcase
    end

endmodule
