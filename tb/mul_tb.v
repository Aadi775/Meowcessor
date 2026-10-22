
`timescale 1ns/1ps
 
module mul_tb;
    parameter WIDTH = 32;
 
    reg  clk = 0;
    reg  rst_n;
    reg  start;
    reg  signed_rs1;
    reg  signed_rs2;
    reg  signed [WIDTH-1:0] a, b;
    wire [2*WIDTH-1:0] product;
    wire done;
 
    integer errors = 0;
    integer tests  = 0;
 
    booth_radix4_multiplier #(.WIDTH(WIDTH)) dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .start      (start),
        .signed_rs1 (signed_rs1),
        .signed_rs2 (signed_rs2),
        .rs1_data   (a),
        .rs2_data   (b),
        .result     (product),
        .done       (done)
    );
 
    always #5 clk = ~clk;
 
    task run_case(input signed [WIDTH-1:0] av, input signed [WIDTH-1:0] bv);
        reg signed [2*WIDTH-1:0] expected;
        begin
            tests = tests + 1;
            signed_rs1 = 1;
            signed_rs2 = 1;
            a = av; b = bv;
            expected = $signed(av) * $signed(bv);
 
            @(posedge clk);
            start = 1;
            @(posedge clk);
            start = 0;
 
            wait(done);
            @(posedge clk); // let product settle/latch
 
            if ($signed(product) !== expected) begin
                errors = errors + 1;
                $display("FAIL a=%0d b=%0d got=%0d exp=%0d", av, bv, $signed(product), expected);
            end
            @(posedge clk);
        end
    endtask

    task run_case_custom(input s1, input s2, input [WIDTH-1:0] av, input [WIDTH-1:0] bv, input [2*WIDTH-1:0] expected);
        begin
            tests = tests + 1;
            signed_rs1 = s1;
            signed_rs2 = s2;
            a = av; b = bv;

            @(posedge clk);
            start = 1;
            @(posedge clk);
            start = 0;

            wait(done);
            @(posedge clk);

            if (product !== expected) begin
                errors = errors + 1;
                $display("FAIL custom s1=%b s2=%b a=%h b=%h got=%h exp=%h", s1, s2, av, bv, product, expected);
            end
            @(posedge clk);
        end
    endtask
 
    integer i;
    reg signed [WIDTH-1:0] ra, rb;
 
    initial begin
        $dumpfile("sim/mul_wave.vcd");
        $dumpvars(0, mul_tb);

        rst_n = 0; start = 0; a = 0; b = 0; signed_rs1 = 1; signed_rs2 = 1;
        #12 rst_n = 1;
 
        run_case(3, -3);
        run_case(-3, 3);
        run_case(-3, -3);
        // Unsigned and mixed-sign tests:
        run_case_custom(0, 0, 32'hFFFF_FFFF, 32'hFFFF_FFFF, 64'hFFFF_FFFE_0000_0001);
        run_case_custom(1, 0, 32'hFFFF_FFFF, 32'h0000_0002, 64'hFFFF_FFFF_FFFF_FFFE);
        run_case(0, 5);
        run_case(5, 0);
        run_case(1, 1);
        run_case(-1, -1);
        run_case(32'sh7FFFFFFF, 1);          // max positive
        run_case(32'sh80000000, 1);          // min negative (edge case)
        run_case(32'sh7FFFFFFF, 32'sh7FFFFFFF); // max*max
 
        for (i = 0; i < 500; i = i + 1) begin
            ra = $random;
            rb = $random;
            run_case(ra, rb);
        end
 
        if (errors == 0)
            $display("ALL %0d TESTS PASSED", tests);
        else
            $display("%0d / %0d TESTS FAILED", errors, tests);
 
        $finish;
    end
endmodule
