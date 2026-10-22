`timescale 1ns/1ps
`include "defines.v"

// ============================================================================
//  Meowcessor Register File + ALU Datapath Integration Testbench
// ============================================================================
//
//  Demonstrates and verifies the coupled datapath loop:
//    1. Register File supplies operands rs1, rs2 to ALU.
//    2. ALU executes requested operation (single-cycle or multi-cycle).
//    3. ALU done pulse latches result back into destination register rd.
//    4. Verifies chained arithmetic dependencies, logic, shifts, multiplication,
//       division, and register x0 immutability.
//
// ============================================================================

module regfile_alu_tb;

    parameter WIDTH      = 32;
    parameter ADDR_WIDTH = 5;

    reg                   clk = 0;
    reg                   rst_n;

    // Regfile controls
    reg                   rf_we;
    reg  [ADDR_WIDTH-1:0] rf_waddr;
    reg  [WIDTH-1:0]      rf_wdata;
    reg  [ADDR_WIDTH-1:0] rf_raddr1;
    reg  [ADDR_WIDTH-1:0] rf_raddr2;
    wire [WIDTH-1:0]      rf_rdata1;
    wire [WIDTH-1:0]      rf_rdata2;

    // ALU controls
    reg                   alu_start;
    reg  [4:0]            alu_op;
    wire [WIDTH-1:0]      alu_result;
    wire [WIDTH-1:0]      alu_result_hi;
    wire                  alu_done;
    wire                  alu_busy;
    wire                  alu_div_by_zero;

    // MUX for register file write data:
    // Either external load (for initializing registers) or ALU result
    reg                   wb_from_alu;
    wire [WIDTH-1:0]      reg_wdata_mux = wb_from_alu ? alu_result : rf_wdata;
    wire                  reg_we_mux    = wb_from_alu ? alu_done   : rf_we;

    integer errors = 0;
    integer tests  = 0;
    integer i;

    // ------------------------------------------------------------------------
    // DUT: Register File
    // ------------------------------------------------------------------------
    regfile #(
        .WIDTH     (WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_regfile (
        .clk   (clk),
        .rst_n (rst_n),
        .we    (reg_we_mux),
        .waddr (rf_waddr),
        .wdata (reg_wdata_mux),
        .raddr1(rf_raddr1),
        .rdata1(rf_rdata1),
        .raddr2(rf_raddr2),
        .rdata2(rf_rdata2)
    );

    // ------------------------------------------------------------------------
    // DUT: ALU (Operands directly driven by Register File read ports)
    // ------------------------------------------------------------------------
    alu #(
        .WIDTH(WIDTH)
    ) u_alu (
        .clk        (clk),
        .rst_n      (rst_n),
        .start      (alu_start),
        .alu_op     (alu_op),
        .rs1_data   (rf_rdata1),
        .rs2_data   (rf_rdata2),
        .result     (alu_result),
        .result_hi  (alu_result_hi),
        .done       (alu_done),
        .busy       (alu_busy),
        .div_by_zero(alu_div_by_zero)
    );

    // 100 MHz clock
    always #5 clk = ~clk;

    // Task: Directly initialize a register (like an immediate load)
    task load_reg(input [ADDR_WIDTH-1:0] addr, input [WIDTH-1:0] data);
    begin
        @(negedge clk);
        wb_from_alu = 1'b0;
        rf_we       = 1'b1;
        rf_waddr    = addr;
        rf_wdata    = data;
        @(posedge clk);
        #1;
        rf_we       = 1'b0;
        rf_waddr    = 0;
        rf_wdata    = 0;
    end
    endtask

    // Task: Execute an R-type instruction: rd = rs1 `op` rs2 via ALU
    task exec_alu_op(
        input [ADDR_WIDTH-1:0] rd,
        input [ADDR_WIDTH-1:0] rs1,
        input [ADDR_WIDTH-1:0] rs2,
        input [4:0]            op
    );
    begin
        @(negedge clk);
        wb_from_alu = 1'b1;
        rf_raddr1   = rs1;
        rf_raddr2   = rs2;
        rf_waddr    = rd;
        alu_op      = op;
        alu_start   = 1'b1;

        @(negedge clk);
        alu_start   = 1'b0;

        // Wait until ALU asserts done
        while (!alu_done) begin
            @(posedge clk);
        end

        // alu_done is 1; regfile clocks in the result on the next posedge clk
        @(posedge clk);
        #1;

        @(negedge clk);
        wb_from_alu = 1'b0;
        rf_waddr    = 0;
    end
    endtask

    // Task: Verify register content
    task verify_reg(input [ADDR_WIDTH-1:0] addr, input [WIDTH-1:0] expected, input [8*20-1:0] name);
    begin
        rf_raddr1 = addr;
        #2;
        tests = tests + 1;
        if (rf_rdata1 === expected) begin
            $display("[PASS] %s: x%0d = 0x%08h (%0d)", name, addr, rf_rdata1, $signed(rf_rdata1));
        end else begin
            $display("[FAIL] %s: x%0d = 0x%08h (%0d), expected 0x%08h (%0d)",
                     name, addr, rf_rdata1, $signed(rf_rdata1), expected, $signed(expected));
            errors = errors + 1;
        end
    end
    endtask

    initial begin
        $dumpfile("sim/regfile_alu_wave.vcd");
        $dumpvars(0, regfile_alu_tb);
        // Icarus Verilog does not dump memory arrays by default — dump each register explicitly
        for (i = 0; i < 32; i = i + 1) begin
            $dumpvars(0, u_regfile.regs[i]);
        end

        // Reset
        rst_n       = 1'b0;
        wb_from_alu = 1'b0;
        rf_we       = 1'b0;
        rf_waddr    = 0;
        rf_wdata    = 0;
        rf_raddr1   = 0;
        rf_raddr2   = 0;
        alu_start   = 1'b0;
        alu_op      = 0;

        #25;
        @(negedge clk);
        rst_n = 1'b1;
        #15;

        $display("==================================================");
        $display("  Starting RegFile + ALU Datapath Integration Tests");
        $display("==================================================");

        // --------------------------------------------------------------------
        // Step 1: Pre-populate base registers
        // --------------------------------------------------------------------
        $display("\n--- Step 1: Initializing test registers ---");
        load_reg(5'd1, 32'd40);        // x1 = 40
        load_reg(5'd2, 32'd12);        // x2 = 12
        load_reg(5'd3, 32'hFFFF_FFF6); // x3 = -10

        verify_reg(5'd1, 32'd40,        "Init x1");
        verify_reg(5'd2, 32'd12,        "Init x2");
        verify_reg(5'd3, 32'hFFFF_FFF6, "Init x3");

        // --------------------------------------------------------------------
        // Step 2: Single-Cycle Arithmetic (ADD, SUB)
        // --------------------------------------------------------------------
        $display("\n--- Step 2: ADD & SUB ---");
        // x4 = x1 + x2 = 40 + 12 = 52
        exec_alu_op(5'd4, 5'd1, 5'd2, `ALU_OP_ADD);
        verify_reg(5'd4, 32'd52, "ADD x4 = x1 + x2");

        // x5 = x4 - x2 = 52 - 12 = 40
        exec_alu_op(5'd5, 5'd4, 5'd2, `ALU_OP_SUB);
        verify_reg(5'd5, 32'd40, "SUB x5 = x4 - x2");

        // --------------------------------------------------------------------
        // Step 3: Shift Operations (SLL, SRL, SRA)
        // --------------------------------------------------------------------
        $display("\n--- Step 3: Shift Operations ---");
        load_reg(5'd6, 32'd2); // shift amount = 2

        // x7 = x1 << x6 = 40 << 2 = 160
        exec_alu_op(5'd7, 5'd1, 5'd6, `ALU_OP_SLL);
        verify_reg(5'd7, 32'd160, "SLL x7 = x1 << x6");

        // x8 = x7 >> x6 = 160 >> 2 = 40
        exec_alu_op(5'd8, 5'd7, 5'd6, `ALU_OP_SRL);
        verify_reg(5'd8, 32'd40, "SRL x8 = x7 >> x6");

        // x9 = x3 >>> x6 = -10 >>> 2 = -3 (32'hFFFF_FFFD)
        exec_alu_op(5'd9, 5'd3, 5'd6, `ALU_OP_SRA);
        verify_reg(5'd9, 32'hFFFF_FFFD, "SRA x9 = x3 >>> x6");

        // --------------------------------------------------------------------
        // Step 4: Logic Operations (AND, OR, XOR)
        // --------------------------------------------------------------------
        $display("\n--- Step 4: Logic Operations ---");
        load_reg(5'd10, 32'h0000_00FF);
        load_reg(5'd11, 32'h0000_0F0F);

        // x12 = x10 & x11 = 0x0000_000F
        exec_alu_op(5'd12, 5'd10, 5'd11, `ALU_OP_AND);
        verify_reg(5'd12, 32'h0000_000F, "AND x12 = x10 & x11");

        // x13 = x10 | x11 = 0x0000_0FFF
        exec_alu_op(5'd13, 5'd10, 5'd11, `ALU_OP_OR);
        verify_reg(5'd13, 32'h0000_0FFF, "OR  x13 = x10 | x11");

        // x14 = x10 ^ x11 = 0x0000_0FF0
        exec_alu_op(5'd14, 5'd10, 5'd11, `ALU_OP_XOR);
        verify_reg(5'd14, 32'h0000_0FF0, "XOR x14 = x10 ^ x11");

        // --------------------------------------------------------------------
        // Step 5: Comparisons (SLT, SLTU)
        // --------------------------------------------------------------------
        $display("\n--- Step 5: Comparisons ---");
        // x3 is -10 (signed < 0), x1 is 40
        // x15 = (x3 < x1) = 1 (signed)
        exec_alu_op(5'd15, 5'd3, 5'd1, `ALU_OP_SLT);
        verify_reg(5'd15, 32'd1, "SLT  x15 = (x3 < x1)");

        // x16 = (x3 < x1) = 0 (unsigned: 0xFFFFFFF6 is not < 40)
        exec_alu_op(5'd16, 5'd3, 5'd1, `ALU_OP_SLTU);
        verify_reg(5'd16, 32'd0, "SLTU x16 = (x3 < x1)");

        // --------------------------------------------------------------------
        // Step 6: Multi-Cycle Multiplication (MUL)
        // --------------------------------------------------------------------
        $display("\n--- Step 6: Multi-cycle Multiplier ---");
        // x17 = x1 * x2 = 40 * 12 = 480
        exec_alu_op(5'd17, 5'd1, 5'd2, `ALU_OP_MUL);
        verify_reg(5'd17, 32'd480, "MUL x17 = x1 * x2");

        // --------------------------------------------------------------------
        // Step 7: Multi-Cycle Division and Remainder (DIV, REM)
        // --------------------------------------------------------------------
        $display("\n--- Step 7: Multi-cycle Divider ---");
        load_reg(5'd18, 32'd7);

        // x19 = x17 / x18 = 480 / 7 = 68
        exec_alu_op(5'd19, 5'd17, 5'd18, `ALU_OP_DIV);
        verify_reg(5'd19, 32'd68, "DIV x19 = x17 / x18");

        // x20 = x17 % x18 = 480 % 7 = 4
        exec_alu_op(5'd20, 5'd17, 5'd18, `ALU_OP_REM);
        verify_reg(5'd20, 32'd4, "REM x20 = x17 % x18");

        // --------------------------------------------------------------------
        // Step 8: Immutability of Register x0 via ALU writeback
        // --------------------------------------------------------------------
        $display("\n--- Step 8: Verify x0 Protection during ALU writeback ---");
        // Attempt: x0 = x1 + x2
        exec_alu_op(5'd0, 5'd1, 5'd2, `ALU_OP_ADD);
        verify_reg(5'd0, 32'd0, "x0 after ALU write attempt");

        // --------------------------------------------------------------------
        // Step 9: Chained Computational Pipeline Simulation
        // --------------------------------------------------------------------
        // Formula: Result = (((x21 + x22) * x23) - x24) / x25
        // Let x21=5, x22=15 -> 20; x23=8 -> 160; x24=10 -> 150; x25=5 -> 30
        $display("\n--- Step 9: Chained Dependency Execution ---");
        load_reg(5'd21, 32'd5);
        load_reg(5'd22, 32'd15);
        load_reg(5'd23, 32'd8);
        load_reg(5'd24, 32'd10);
        load_reg(5'd25, 32'd5);

        // x26 = x21 + x22 = 20
        exec_alu_op(5'd26, 5'd21, 5'd22, `ALU_OP_ADD);
        verify_reg(5'd26, 32'd20, "Chain Add (20)");

        // x27 = x26 * x23 = 20 * 8 = 160
        exec_alu_op(5'd27, 5'd26, 5'd23, `ALU_OP_MUL);
        verify_reg(5'd27, 32'd160, "Chain Mul (160)");

        // x28 = x27 - x24 = 160 - 10 = 150
        exec_alu_op(5'd28, 5'd27, 5'd24, `ALU_OP_SUB);
        verify_reg(5'd28, 32'd150, "Chain Sub (150)");

        // x29 = x28 / x25 = 150 / 5 = 30
        exec_alu_op(5'd29, 5'd28, 5'd25, `ALU_OP_DIV);
        verify_reg(5'd29, 32'd30, "Chain Div (30)");

        // --------------------------------------------------------------------
        // Final Summary
        // --------------------------------------------------------------------
        #50;
        $display("\n==================================================");
        if (errors == 0) begin
            $display("  ALL %0d INTEGRATION TESTS PASSED!", tests);
            $display("  Register File <--> ALU Datapath fully validated!");
        end else begin
            $display("  %0d / %0d INTEGRATION TESTS FAILED!", errors, tests);
        end
        $display("==================================================");

        $finish;
    end

endmodule
