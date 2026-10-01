`timescale 1ns/1ps
`include "defines.v"

// ============================================================================
//  Meowcessor Register File — Comprehensive Testbench
// ============================================================================
//
//  Coverage:
//    1. Reset condition: All 32 registers initialized to 0.
//    2. Zero Register (x0) isolation: Writes to x0 ignored; x0 always reads 0.
//    3. Full Write/Read sweep across registers x1 to x31.
//    4. Dual-port concurrent reads: Reading distinct registers simultaneously.
//    5. Internal Write-Through Bypass / Forwarding:
//       - Reading waddr while we=1 returns wdata combinatorially.
//       - Forwarding to x0 suppressed (x0 never forwards non-zero).
//    6. Randomized stress test with shadow software register array.
//
// ============================================================================

module regfile_tb;

    parameter WIDTH      = 32;
    parameter ADDR_WIDTH = 5;
    localparam NUM_REGS  = 32;

    reg                   clk = 0;
    reg                   rst_n;
    reg                   we;
    reg  [ADDR_WIDTH-1:0] waddr;
    reg  [WIDTH-1:0]      wdata;
    reg  [ADDR_WIDTH-1:0] raddr1;
    wire [WIDTH-1:0]      rdata1;
    reg  [ADDR_WIDTH-1:0] raddr2;
    wire [WIDTH-1:0]      rdata2;

    integer errors = 0;
    integer tests  = 0;

    // Instantiate DUT
    regfile #(
        .WIDTH     (WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) dut (
        .clk   (clk),
        .rst_n (rst_n),
        .we    (we),
        .waddr (waddr),
        .wdata (wdata),
        .raddr1(raddr1),
        .rdata1(rdata1),
        .raddr2(raddr2),
        .rdata2(rdata2)
    );

    // 100 MHz clock generation (10ns period)
    always #5 clk = ~clk;

    // Shadow register model for random testing
    reg [WIDTH-1:0] shadow_regs [0:NUM_REGS-1];
    integer i, step;
    reg [WIDTH-1:0] test_val;
    reg [ADDR_WIDTH-1:0] rand_r1, rand_r2, rand_w;
    reg [WIDTH-1:0] rand_data;

    // Helper write task
    task write_reg(input [ADDR_WIDTH-1:0] addr, input [WIDTH-1:0] data);
    begin
        @(negedge clk);
        we    = 1'b1;
        waddr = addr;
        wdata = data;
        @(posedge clk);
        #1;
        we    = 1'b0;
        waddr = 0;
        wdata = 0;
    end
    endtask

    initial begin
        $dumpfile("sim/regfile_wave.vcd");
        $dumpvars(0, regfile_tb);
        // Icarus Verilog does not dump memory arrays by default — dump each register explicitly
        for (i = 0; i < NUM_REGS; i = i + 1) begin
            $dumpvars(0, dut.regs[i]);
        end

        // Initialize inputs
        rst_n  = 1'b0;
        we     = 1'b0;
        waddr  = 0;
        wdata  = 0;
        raddr1 = 0;
        raddr2 = 0;

        // Reset pulse
        #20;
        @(negedge clk);
        rst_n = 1'b1;
        #10;

        $display("==================================================");
        $display("  Running Register File Test Suite");
        $display("==================================================");

        // --------------------------------------------------------------------
        // Test 1: Reset Check (All 32 registers should read 0)
        // --------------------------------------------------------------------
        $display("[Test 1] Reset verification for all registers...");
        for (i = 0; i < NUM_REGS; i = i + 1) begin
            raddr1 = i[ADDR_WIDTH-1:0];
            raddr2 = (NUM_REGS - 1 - i);
            #1;
            tests = tests + 2;
            if (rdata1 !== 32'h0) begin
                $display("ERROR: reg x%0d after reset = 0x%08h, expected 0x0", i, rdata1);
                errors = errors + 1;
            end
            if (rdata2 !== 32'h0) begin
                $display("ERROR: reg x%0d after reset = 0x%08h, expected 0x0", NUM_REGS-1-i, rdata2);
                errors = errors + 1;
            end
        end

        // --------------------------------------------------------------------
        // Test 2: Hardwired Zero Register (x0) Write Protection
        // --------------------------------------------------------------------
        $display("[Test 2] Verifying x0 is read-only and always zero...");
        write_reg(5'd0, 32'hDEADBEEF);
        write_reg(5'd0, 32'hFFFFFFFF);

        raddr1 = 5'd0;
        raddr2 = 5'd0;
        #1;
        tests = tests + 2;
        if (rdata1 !== 32'h0) begin
            $display("ERROR: x0 modified via Port 1! Value = 0x%08h", rdata1);
            errors = errors + 1;
        end
        if (rdata2 !== 32'h0) begin
            $display("ERROR: x0 modified via Port 2! Value = 0x%08h", rdata2);
            errors = errors + 1;
        end

        // --------------------------------------------------------------------
        // Test 3: Write and Read Sweep across x1 to x31
        // --------------------------------------------------------------------
        $display("[Test 3] Writing unique test patterns to x1..x31...");
        for (i = 1; i < NUM_REGS; i = i + 1) begin
            test_val = 32'hA000_0000 | (i << 16) | (32'h55AA ^ i);
            write_reg(i[ADDR_WIDTH-1:0], test_val);
            shadow_regs[i] = test_val;
        end
        shadow_regs[0] = 32'h0;

        // Read back and verify
        for (i = 1; i < NUM_REGS; i = i + 1) begin
            raddr1 = i[ADDR_WIDTH-1:0];
            #1;
            tests = tests + 1;
            if (rdata1 !== shadow_regs[i]) begin
                $display("ERROR: Read mismatch at x%0d! Got 0x%08h, expected 0x%08h",
                         i, rdata1, shadow_regs[i]);
                errors = errors + 1;
            end
        end

        // --------------------------------------------------------------------
        // Test 4: Dual-Port Concurrent Reads
        // --------------------------------------------------------------------
        $display("[Test 4] Verifying concurrent dual-port reads...");
        for (i = 0; i < NUM_REGS; i = i + 1) begin
            raddr1 = i[ADDR_WIDTH-1:0];
            raddr2 = (31 - i);
            #1;
            tests = tests + 2;
            if (rdata1 !== shadow_regs[i]) begin
                $display("ERROR: Port 1 concurrent read x%0d: got 0x%08h, exp 0x%08h",
                         i, rdata1, shadow_regs[i]);
                errors = errors + 1;
            end
            if (rdata2 !== shadow_regs[31 - i]) begin
                $display("ERROR: Port 2 concurrent read x%0d: got 0x%08h, exp 0x%08h",
                         31 - i, rdata2, shadow_regs[31 - i]);
                errors = errors + 1;
            end
        end

        // --------------------------------------------------------------------
        // Test 5: Internal Write-Through Bypass / Forwarding
        // --------------------------------------------------------------------
        $display("[Test 5] Testing write-through bypass / forwarding...");
        @(negedge clk);
        we     = 1'b1;
        waddr  = 5'd7;
        wdata  = 32'h1234_5678;
        raddr1 = 5'd7;   // Read port 1 same cycle as write
        raddr2 = 5'd7;   // Read port 2 same cycle as write
        #1;
        tests = tests + 2;
        if (rdata1 !== 32'h1234_5678) begin
            $display("ERROR: Write-through bypass failed on Port 1! Got 0x%08h", rdata1);
            errors = errors + 1;
        end
        if (rdata2 !== 32'h1234_5678) begin
            $display("ERROR: Write-through bypass failed on Port 2! Got 0x%08h", rdata2);
            errors = errors + 1;
        end

        // Clock this write so reg x7 actually stores 32'h1234_5678
        @(posedge clk);
        #1;
        shadow_regs[7] = 32'h1234_5678;

        // Check that writing to x0 DOES NOT bypass/forward non-zero
        @(negedge clk);
        waddr  = 5'd0;
        wdata  = 32'hFEED_FACE;
        raddr1 = 5'd0;
        raddr2 = 5'd0;
        #1;
        tests = tests + 2;
        if (rdata1 !== 32'h0) begin
            $display("ERROR: Write-through bypass leaked non-zero to x0 on Port 1! Got 0x%08h", rdata1);
            errors = errors + 1;
        end
        if (rdata2 !== 32'h0) begin
            $display("ERROR: Write-through bypass leaked non-zero to x0 on Port 2! Got 0x%08h", rdata2);
            errors = errors + 1;
        end

        @(posedge clk);
        #1;
        we    = 1'b0;
        waddr = 0;
        wdata = 0;

        // --------------------------------------------------------------------
        // Test 6: Randomized Stress Test (500 iterations)
        // --------------------------------------------------------------------
        $display("[Test 6] Running 500 randomized write/read operations...");
        for (step = 0; step < 500; step = step + 1) begin
            rand_w    = $random % NUM_REGS;
            rand_data = $random;
            rand_r1   = $random % NUM_REGS;
            rand_r2   = $random % NUM_REGS;

            @(negedge clk);
            we     = ($random % 4 != 0); // 75% chance of write
            waddr  = rand_w;
            wdata  = rand_data;
            raddr1 = rand_r1;
            raddr2 = rand_r2;

            #1;
            // Check combinational read (including potential bypass)
            tests = tests + 2;
            test_val = (we && (waddr == rand_r1) && (waddr != 0)) ? rand_data : shadow_regs[rand_r1];
            if (rdata1 !== test_val) begin
                $display("ERROR: Step %0d: Port 1 read mismatch! raddr=%0d, got 0x%08h, exp 0x%08h",
                         step, rand_r1, rdata1, test_val);
                errors = errors + 1;
            end

            test_val = (we && (waddr == rand_r2) && (waddr != 0)) ? rand_data : shadow_regs[rand_r2];
            if (rdata2 !== test_val) begin
                $display("ERROR: Step %0d: Port 2 read mismatch! raddr=%0d, got 0x%08h, exp 0x%08h",
                         step, rand_r2, rdata2, test_val);
                errors = errors + 1;
            end

            @(posedge clk);
            #1;
            if (we && rand_w != 0) begin
                shadow_regs[rand_w] = rand_data;
            end
        end

        we = 1'b0;
        #20;

        // --------------------------------------------------------------------
        // Final Summary
        // --------------------------------------------------------------------
        $display("==================================================");
        if (errors == 0) begin
            $display("  ALL %0d REGFILE TESTS PASSED!", tests);
        end else begin
            $display("  %0d / %0d REGFILE TESTS FAILED!", errors, tests);
        end
        $display("==================================================");

        $finish;
    end

endmodule
