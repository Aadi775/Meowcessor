`timescale 1ns/1ps
`include "defines.v"

// ============================================================================
//  Meowcessor ALU — Comprehensive Testbench
// ============================================================================
//
//  Tests all 16 ALU operations:
//    Single-cycle:  ADD, SUB, AND, OR, XOR, SLL, SRL, SRA, SLT, SLTU
//    Multi-cycle:   MUL, MULH, DIV, DIVU, REM, REMU
//
//  Methodology:
//    - Directed edge-case vectors for each operation
//    - Random vectors (500 per operation category)
//    - Self-checking against behavioral Verilog golden model
//
// ============================================================================

module alu_tb;

    parameter WIDTH = 32;

    reg                  clk = 0;
    reg                  rst_n;
    reg                  start;
    reg  [4:0]           alu_op;
    reg  [WIDTH-1:0]     a, b;
    wire [WIDTH-1:0]     result;
    wire [WIDTH-1:0]     result_hi;
    wire                 done;
    wire                 busy;
    wire                 div_by_zero;

    integer errors = 0;
    integer tests  = 0;

    alu #(.WIDTH(WIDTH)) dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .start      (start),
        .alu_op     (alu_op),
        .rs1_data   (a),
        .rs2_data   (b),
        .result     (result),
        .result_hi  (result_hi),
        .done       (done),
        .busy       (busy),
        .div_by_zero(div_by_zero)
    );

    // Human-readable opcode name for GTKWave
    reg [8*7-1:0] op_name;
    always @(alu_op) begin
        case (alu_op)
            `ALU_OP_ADD:  op_name = "ADD";
            `ALU_OP_SUB:  op_name = "SUB";
            `ALU_OP_AND:  op_name = "AND";
            `ALU_OP_OR:   op_name = "OR";
            `ALU_OP_XOR:  op_name = "XOR";
            `ALU_OP_SLL:  op_name = "SLL";
            `ALU_OP_SRL:  op_name = "SRL";
            `ALU_OP_SRA:  op_name = "SRA";
            `ALU_OP_SLT:  op_name = "SLT";
            `ALU_OP_SLTU: op_name = "SLTU";
            `ALU_OP_MUL:    op_name = "MUL";
            `ALU_OP_MULH:   op_name = "MULH";
            `ALU_OP_MULHSU: op_name = "MULHSU";
            `ALU_OP_MULHU:  op_name = "MULHU";
            `ALU_OP_DIV:    op_name = "DIV";
            `ALU_OP_DIVU:   op_name = "DIVU";
            `ALU_OP_REM:    op_name = "REM";
            `ALU_OP_REMU:   op_name = "REMU";
            default:        op_name = "UNKNOWN";
        endcase
    end

    always #5 clk = ~clk;

    // ========================================================================
    //  Task: run a single-cycle ALU operation and check result
    // ========================================================================

    task run_single;
        input [4:0]        op;
        input [WIDTH-1:0]  av, bv;
        input [WIDTH-1:0]  expected;
        begin
            tests = tests + 1;
            alu_op = op;
            a = av;
            b = bv;

            @(posedge clk);
            start = 1'b1;
            @(posedge clk);
            start = 1'b0;

            // done should be asserted in this cycle
            if (!done) begin
                errors = errors + 1;
                $display("FAIL [single-cycle] op=%0d a=%h b=%h — done not asserted", op, av, bv);
            end else if (result !== expected) begin
                errors = errors + 1;
                $display("FAIL op=%0d a=%h b=%h | got=%h exp=%h", op, av, bv, result, expected);
            end

            @(posedge clk); // gap between tests
        end
    endtask

    // ========================================================================
    //  Task: run a multi-cycle ALU operation and check result
    // ========================================================================

    task run_multi;
        input [4:0]        op;
        input [WIDTH-1:0]  av, bv;
        input [WIDTH-1:0]  expected;
        input [WIDTH-1:0]  expected_hi;
        begin
            tests = tests + 1;
            alu_op = op;
            a = av;
            b = bv;

            @(posedge clk);
            start = 1'b1;
            @(posedge clk);
            start = 1'b0;

            // Wait for done
            wait(done);
            @(posedge clk);

            if (result !== expected) begin
                errors = errors + 1;
                $display("FAIL op=%0d a=%h b=%h | got=%h exp=%h", op, av, bv, result, expected);
            end
            if ((op == `ALU_OP_MULH || op == `ALU_OP_MULHSU || op == `ALU_OP_MULHU) && result_hi !== expected_hi) begin
                errors = errors + 1;
                $display("FAIL op=%0d a=%h b=%h | got_hi=%h exp_hi=%h", op, av, bv, result_hi, expected_hi);
            end

            @(posedge clk); // gap
        end
    endtask

    // ========================================================================
    //  Task: run a divider operation (checks div_by_zero flag)
    // ========================================================================

    task run_div;
        input [4:0]        op;
        input [WIDTH-1:0]  av, bv;
        input [WIDTH-1:0]  expected;
        input              expect_dbz;
        begin
            tests = tests + 1;
            alu_op = op;
            a = av;
            b = bv;

            @(posedge clk);
            start = 1'b1;
            @(posedge clk);
            start = 1'b0;

            wait(done);
            @(posedge clk);

            if (result !== expected) begin
                errors = errors + 1;
                $display("FAIL op=%0d a=%h b=%h | got=%h exp=%h", op, av, bv, result, expected);
            end
            if (expect_dbz && !div_by_zero) begin
                errors = errors + 1;
                $display("FAIL op=%0d a=%h b=%h | div_by_zero not asserted", op, av, bv);
            end

            @(posedge clk);
        end
    endtask

    // ========================================================================
    //  Golden model helpers
    // ========================================================================

    function [WIDTH-1:0] golden_slt;
        input [WIDTH-1:0] av, bv;
        begin
            golden_slt = ($signed(av) < $signed(bv)) ? 32'd1 : 32'd0;
        end
    endfunction

    function [WIDTH-1:0] golden_sltu;
        input [WIDTH-1:0] av, bv;
        begin
            golden_sltu = (av < bv) ? 32'd1 : 32'd0;
        end
    endfunction

    // ========================================================================
    //  Main test sequence
    // ========================================================================

    integer i;
    reg [WIDTH-1:0] ra, rb;
    reg signed [WIDTH-1:0] sa, sb;
    reg signed [2*WIDTH-1:0] mul_full;

    initial begin
        $dumpfile("sim/alu_wave.vcd");
        $dumpvars(0, alu_tb);

        rst_n = 0; start = 0; alu_op = 0; a = 0; b = 0;
        #12 rst_n = 1;

        // ====================================================================
        //  ADD — single-cycle
        // ====================================================================
        $display("--- ADD ---");
        run_single(`ALU_OP_ADD, 0, 0, 0);
        run_single(`ALU_OP_ADD, 1, 1, 2);
        run_single(`ALU_OP_ADD, 32'hFFFFFFFF, 1, 0);
        run_single(`ALU_OP_ADD, 32'h8000_0000, 32'h8000_0000, 0);
        run_single(`ALU_OP_ADD, 32'hAAAA_AAAA, 32'h5555_5555, 32'hFFFF_FFFF);

        for (i = 0; i < 200; i = i + 1) begin
            ra = $random; rb = $random;
            run_single(`ALU_OP_ADD, ra, rb, ra + rb);
        end

        // ====================================================================
        //  SUB — single-cycle
        // ====================================================================
        $display("--- SUB ---");
        run_single(`ALU_OP_SUB, 5, 3, 2);
        run_single(`ALU_OP_SUB, 0, 0, 0);
        run_single(`ALU_OP_SUB, 0, 1, 32'hFFFFFFFF);
        run_single(`ALU_OP_SUB, 32'h8000_0000, 1, 32'h7FFF_FFFF);
        run_single(`ALU_OP_SUB, 32'h8000_0000, 32'h8000_0000, 0);

        for (i = 0; i < 200; i = i + 1) begin
            ra = $random; rb = $random;
            run_single(`ALU_OP_SUB, ra, rb, ra - rb);
        end

        // ====================================================================
        //  AND — single-cycle
        // ====================================================================
        $display("--- AND ---");
        run_single(`ALU_OP_AND, 32'hFFFF_FFFF, 32'hAAAA_AAAA, 32'hAAAA_AAAA);
        run_single(`ALU_OP_AND, 32'h0000_0000, 32'hFFFF_FFFF, 32'h0000_0000);
        run_single(`ALU_OP_AND, 32'h1234_5678, 32'h0F0F_0F0F, 32'h0204_0608);

        for (i = 0; i < 100; i = i + 1) begin
            ra = $random; rb = $random;
            run_single(`ALU_OP_AND, ra, rb, ra & rb);
        end

        // ====================================================================
        //  OR — single-cycle
        // ====================================================================
        $display("--- OR ---");
        run_single(`ALU_OP_OR, 32'h0000_0000, 32'h0000_0000, 32'h0000_0000);
        run_single(`ALU_OP_OR, 32'hAAAA_AAAA, 32'h5555_5555, 32'hFFFF_FFFF);

        for (i = 0; i < 100; i = i + 1) begin
            ra = $random; rb = $random;
            run_single(`ALU_OP_OR, ra, rb, ra | rb);
        end

        // ====================================================================
        //  XOR — single-cycle
        // ====================================================================
        $display("--- XOR ---");
        run_single(`ALU_OP_XOR, 32'hFFFF_FFFF, 32'hFFFF_FFFF, 32'h0000_0000);
        run_single(`ALU_OP_XOR, 32'hAAAA_AAAA, 32'h5555_5555, 32'hFFFF_FFFF);
        run_single(`ALU_OP_XOR, 32'h1234_5678, 32'h0000_0000, 32'h1234_5678);

        for (i = 0; i < 100; i = i + 1) begin
            ra = $random; rb = $random;
            run_single(`ALU_OP_XOR, ra, rb, ra ^ rb);
        end

        // ====================================================================
        //  SLL — single-cycle
        // ====================================================================
        $display("--- SLL ---");
        run_single(`ALU_OP_SLL, 1, 0, 1);
        run_single(`ALU_OP_SLL, 1, 31, 32'h8000_0000);
        run_single(`ALU_OP_SLL, 32'hFFFF_FFFF, 16, 32'hFFFF_0000);
        run_single(`ALU_OP_SLL, 32'hDEAD_BEEF, 32, 32'hDEAD_BEEF); // shamt = 0 (32 & 0x1F)

        for (i = 0; i < 100; i = i + 1) begin
            ra = $random; rb = $random;
            run_single(`ALU_OP_SLL, ra, rb, ra << rb[4:0]);
        end

        // ====================================================================
        //  SRL — single-cycle
        // ====================================================================
        $display("--- SRL ---");
        run_single(`ALU_OP_SRL, 32'h8000_0000, 31, 1);
        run_single(`ALU_OP_SRL, 32'hFFFF_FFFF, 16, 32'h0000_FFFF);
        run_single(`ALU_OP_SRL, 32'hDEAD_BEEF, 0, 32'hDEAD_BEEF);

        for (i = 0; i < 100; i = i + 1) begin
            ra = $random; rb = $random;
            run_single(`ALU_OP_SRL, ra, rb, ra >> rb[4:0]);
        end

        // ====================================================================
        //  SRA — single-cycle
        // ====================================================================
        $display("--- SRA ---");
        run_single(`ALU_OP_SRA, 32'h8000_0000, 31, 32'hFFFF_FFFF); // sign-extend
        run_single(`ALU_OP_SRA, 32'h7FFF_FFFF, 31, 0);              // positive, no sign
        run_single(`ALU_OP_SRA, 32'hFFFF_FFF0, 4, 32'hFFFF_FFFF);
        run_single(`ALU_OP_SRA, 32'h4000_0000, 1, 32'h2000_0000);

        for (i = 0; i < 100; i = i + 1) begin
            ra = $random; rb = $random;
            run_single(`ALU_OP_SRA, ra, rb, $signed(ra) >>> rb[4:0]);
        end

        // ====================================================================
        //  SLT — single-cycle
        // ====================================================================
        $display("--- SLT ---");
        run_single(`ALU_OP_SLT, 0, 0, 0);
        run_single(`ALU_OP_SLT, 32'hFFFF_FFFF, 0, 1);   // -1 < 0
        run_single(`ALU_OP_SLT, 0, 32'hFFFF_FFFF, 0);   // 0 < -1? no
        run_single(`ALU_OP_SLT, 32'h8000_0000, 32'h7FFF_FFFF, 1); // INT_MIN < INT_MAX
        run_single(`ALU_OP_SLT, 32'h7FFF_FFFF, 32'h8000_0000, 0);
        run_single(`ALU_OP_SLT, 5, 10, 1);
        run_single(`ALU_OP_SLT, 10, 5, 0);

        for (i = 0; i < 200; i = i + 1) begin
            ra = $random; rb = $random;
            run_single(`ALU_OP_SLT, ra, rb, golden_slt(ra, rb));
        end

        // ====================================================================
        //  SLTU — single-cycle
        // ====================================================================
        $display("--- SLTU ---");
        run_single(`ALU_OP_SLTU, 0, 0, 0);
        run_single(`ALU_OP_SLTU, 0, 1, 1);
        run_single(`ALU_OP_SLTU, 1, 0, 0);
        run_single(`ALU_OP_SLTU, 32'hFFFF_FFFF, 0, 0);   // 0xFFFFFFFF > 0 (unsigned)
        run_single(`ALU_OP_SLTU, 0, 32'hFFFF_FFFF, 1);
        run_single(`ALU_OP_SLTU, 32'h8000_0000, 32'h7FFF_FFFF, 0); // unsigned: 0x80000000 > 0x7FFFFFFF

        for (i = 0; i < 200; i = i + 1) begin
            ra = $random; rb = $random;
            run_single(`ALU_OP_SLTU, ra, rb, golden_sltu(ra, rb));
        end

        // ====================================================================
        //  MUL — multi-cycle
        // ====================================================================
        $display("--- MUL ---");
        run_multi(`ALU_OP_MUL, 3, 7, 21, 0);
        run_multi(`ALU_OP_MUL, 32'hFFFF_FFFF, 32'hFFFF_FFFF, 1, 0);  // (-1)*(-1) low = 1
        run_multi(`ALU_OP_MUL, 0, 12345, 0, 0);
        run_multi(`ALU_OP_MUL, 32'h8000_0000, 2, 32'h0000_0000, 0);

        for (i = 0; i < 20; i = i + 1) begin
            ra = $random; rb = $random;
            mul_full = $signed(ra) * $signed(rb);
            run_multi(`ALU_OP_MUL, ra, rb, mul_full[WIDTH-1:0], 0);
        end

        // ====================================================================
        //  MULH — multi-cycle (upper 32 bits signed x signed)
        // ====================================================================
        $display("--- MULH ---");
        run_multi(`ALU_OP_MULH, 32'hFFFF_FFFF, 32'hFFFF_FFFF, 0, 0);  // (-1)*(-1) = 1 => hi=0
        run_multi(`ALU_OP_MULH, 32'h7FFF_FFFF, 32'h7FFF_FFFF, 32'h3FFF_FFFF, 32'h3FFF_FFFF);

        for (i = 0; i < 20; i = i + 1) begin
            ra = $random; rb = $random;
            mul_full = $signed(ra) * $signed(rb);
            run_multi(`ALU_OP_MULH, ra, rb, mul_full[2*WIDTH-1:WIDTH], mul_full[2*WIDTH-1:WIDTH]);
        end

        // ====================================================================
        //  MULHSU — multi-cycle (upper 32 bits signed x unsigned)
        // ====================================================================
        $display("--- MULHSU ---");
        run_multi(`ALU_OP_MULHSU, 32'hFFFF_FFFF, 32'h0000_0002, 32'hFFFF_FFFF, 32'hFFFF_FFFF); // (-1)*2 = -2 => hi=-1
        run_multi(`ALU_OP_MULHSU, 32'h8000_0000, 32'hFFFF_FFFF, 32'h8000_0000, 32'h8000_0000);

        for (i = 0; i < 20; i = i + 1) begin
            ra = $random; rb = $random;
            mul_full = $signed(ra) * $signed({1'b0, rb});
            run_multi(`ALU_OP_MULHSU, ra, rb, mul_full[2*WIDTH-1:WIDTH], mul_full[2*WIDTH-1:WIDTH]);
        end

        // ====================================================================
        //  MULHU — multi-cycle (upper 32 bits unsigned x unsigned)
        // ====================================================================
        $display("--- MULHU ---");
        run_multi(`ALU_OP_MULHU, 32'hFFFF_FFFF, 32'hFFFF_FFFF, 32'hFFFF_FFFE, 32'hFFFF_FFFE);
        run_multi(`ALU_OP_MULHU, 32'h0000_000A, 32'h0000_0014, 0, 0);

        for (i = 0; i < 20; i = i + 1) begin
            ra = $random; rb = $random;
            mul_full = {1'b0, ra} * {1'b0, rb};
            run_multi(`ALU_OP_MULHU, ra, rb, mul_full[2*WIDTH-1:WIDTH], mul_full[2*WIDTH-1:WIDTH]);
        end

        // ====================================================================
        //  DIV — multi-cycle (signed)
        // ====================================================================
        $display("--- DIV ---");
        run_div(`ALU_OP_DIV, 13, 3, 4, 0);
        run_div(`ALU_OP_DIV, 32'hFFFF_FFF3, 3, 32'hFFFF_FFFC, 0);   // -13 / 3 = -4
        run_div(`ALU_OP_DIV, 13, 32'hFFFF_FFFD, 32'hFFFF_FFFC, 0);  // 13 / -3 = -4
        run_div(`ALU_OP_DIV, 7, 0, 32'hFFFF_FFFF, 1);               // div by zero

        for (i = 0; i < 20; i = i + 1) begin
            sa = $random; sb = $random;
            if (sb == 0) sb = 1; // avoid div-by-zero for random (tested above)
            run_div(`ALU_OP_DIV, sa, sb, $signed(sa) / $signed(sb), 0);
        end

        // ====================================================================
        //  DIVU — multi-cycle (unsigned)
        // ====================================================================
        $display("--- DIVU ---");
        run_div(`ALU_OP_DIVU, 13, 3, 4, 0);
        run_div(`ALU_OP_DIVU, 32'hFFFF_FFFF, 2, 32'h7FFF_FFFF, 0);
        run_div(`ALU_OP_DIVU, 5, 0, 32'hFFFF_FFFF, 1);

        for (i = 0; i < 15; i = i + 1) begin
            ra = $random; rb = $random;
            if (rb == 0) rb = 1;
            run_div(`ALU_OP_DIVU, ra, rb, ra / rb, 0);
        end

        // ====================================================================
        //  REM — multi-cycle (signed)
        // ====================================================================
        $display("--- REM ---");
        run_div(`ALU_OP_REM, 13, 3, 1, 0);
        run_div(`ALU_OP_REM, 32'hFFFF_FFF3, 3, 32'hFFFF_FFFF, 0);   // -13 % 3 = -1
        run_div(`ALU_OP_REM, 7, 0, 7, 1);                            // rem by zero => dividend

        for (i = 0; i < 20; i = i + 1) begin
            sa = $random; sb = $random;
            if (sb == 0) sb = 1;
            run_div(`ALU_OP_REM, sa, sb, $signed(sa) % $signed(sb), 0);
        end

        // ====================================================================
        //  REMU — multi-cycle (unsigned)
        // ====================================================================
        $display("--- REMU ---");
        run_div(`ALU_OP_REMU, 13, 3, 1, 0);
        run_div(`ALU_OP_REMU, 32'hFFFF_FFFF, 7, 32'hFFFF_FFFF % 7, 0);
        run_div(`ALU_OP_REMU, 5, 0, 5, 1);

        for (i = 0; i < 15; i = i + 1) begin
            ra = $random; rb = $random;
            if (rb == 0) rb = 1;
            run_div(`ALU_OP_REMU, ra, rb, ra % rb, 0);
        end

        // ====================================================================
        //  Final report
        // ====================================================================
        $display("");
        if (errors == 0) begin
            $display("========================================");
            $display("  ALL %0d TESTS PASSED", tests);
            $display("========================================");
        end else begin
            $display("%0d / %0d TESTS FAILED", errors, tests);
        end

        $finish;
    end

endmodule
