`include "defines.v"

// ============================================================================
//  Meowcessor Register File — RV32I 32-Bit General-Purpose Register File
// ============================================================================
//
//  Architecture:
//    - 32 general-purpose 32-bit registers (x0 to x31).
//    - Register x0 is hardwired to 0 (reads always return 0; writes ignored).
//    - Active-low asynchronous reset (rst_n) clears all registers to 0.
//    - Dual asynchronous/combinational read ports (rs1, rs2).
//    - Single synchronous write port (rd) sampled on posedge clk when we=1.
//    - Internal write-through forwarding (bypass): reading a register currently
//      being written returns the new wdata immediately within the same cycle.
//
// ============================================================================

module regfile #(
    parameter WIDTH      = `XLEN,
    parameter ADDR_WIDTH = `REG_ADDR_LEN
)(
    input  wire                  clk,
    input  wire                  rst_n,

    // Write Port (Synchronous)
    input  wire                  we,
    input  wire [ADDR_WIDTH-1:0] waddr,
    input  wire [WIDTH-1:0]      wdata,

    // Read Port 1 (Asynchronous)
    input  wire [ADDR_WIDTH-1:0] raddr1,
    output wire [WIDTH-1:0]      rdata1,

    // Read Port 2 (Asynchronous)
    input  wire [ADDR_WIDTH-1:0] raddr2,
    output wire [WIDTH-1:0]      rdata2
);

    localparam NUM_REGS = 1 << ADDR_WIDTH;

    // Register storage array: registers x0 through x31
    reg [WIDTH-1:0] regs [0:NUM_REGS-1];

    integer i;

    // ========================================================================
    //  Synchronous Write Operation with Asynchronous Reset
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < NUM_REGS; i = i + 1) begin
                regs[i] <= {WIDTH{1'b0}};
            end
        end else begin
            // x0 is hardwired to 0: ignore writes where waddr == 0
            if (we && (waddr != {ADDR_WIDTH{1'b0}})) begin
                regs[waddr] <= wdata;
            end
        end
    end

    // ========================================================================
    //  Asynchronous Read Operation with Internal Write-Through Forwarding
    // ========================================================================
    //  Port 1:
    assign rdata1 = (!rst_n || (raddr1 == {ADDR_WIDTH{1'b0}})) ? {WIDTH{1'b0}} :
                    (we && (waddr == raddr1))                   ? wdata :
                                                                 regs[raddr1];

    //  Port 2:
    assign rdata2 = (!rst_n || (raddr2 == {ADDR_WIDTH{1'b0}})) ? {WIDTH{1'b0}} :
                    (we && (waddr == raddr2))                   ? wdata :
                                                                 regs[raddr2];

endmodule
