`timescale 1ns/1ps
module srt_tb;
    parameter WIDTH = 32;
    reg clk=0, rst_n, start, signed_mode;
    reg [WIDTH-1:0] a, b;
    wire [WIDTH-1:0] quotient, remainder;
    wire done, busy, div_by_zero;
 
    integer errors=0, tests=0;
 
    radix4_srt_divider #(.WIDTH(WIDTH)) dut(
        .clk(clk), .rst_n(rst_n), .start(start), .signed_mode(signed_mode),
        .rs1_data(a), .rs2_data(b),
        .quotient(quotient), .remainder(remainder),
        .done(done), .busy(busy), .div_by_zero(div_by_zero)
    );
 
    always #5 clk = ~clk;
 
    task run_signed(input signed [WIDTH-1:0] dv, input signed [WIDTH-1:0] ds);
        reg signed [WIDTH-1:0] exp_q, exp_r;
        begin
            tests = tests + 1;
            a = dv; b = ds; signed_mode = 1;
            if (ds == 0) begin
                exp_q = -1;   // all-ones as a signed literal, no unsigned-literal contamination
                exp_r = dv;
            end else begin
                exp_q = dv / ds;   // now a pure signed expression, no mixed-sign ternary
                exp_r = dv % ds;
            end
 
            @(posedge clk); start=1;
            @(posedge clk); start=0;
            wait(done);
            @(posedge clk);
 
            if (ds == 0) begin
                if (!div_by_zero || quotient !== 32'hFFFFFFFF || remainder !== dv) begin
                    errors=errors+1;
                    $display("FAIL(signed div0) dv=%0d ds=%0d got q=%h r=%h dbz=%b",
                              dv, ds, quotient, remainder, div_by_zero);
                end
            end else if ($signed(quotient) !== exp_q || $signed(remainder) !== exp_r) begin
                errors=errors+1;
                $display("FAIL(signed) dv=%0d ds=%0d got q=%0d r=%0d exp q=%0d r=%0d",
                          dv, ds, $signed(quotient), $signed(remainder), exp_q, exp_r);
            end
            @(posedge clk);
        end
    endtask
 
    task run_unsigned(input [WIDTH-1:0] dv, input [WIDTH-1:0] ds);
        reg [WIDTH-1:0] exp_q, exp_r;
        begin
            tests = tests + 1;
            a = dv; b = ds; signed_mode = 0;
            if (ds == 0) begin
                exp_q = {WIDTH{1'b1}};
                exp_r = dv;
            end else begin
                exp_q = dv / ds;
                exp_r = dv % ds;
            end
 
            @(posedge clk); start=1;
            @(posedge clk); start=0;
            wait(done);
            @(posedge clk);
 
            if (ds == 0) begin
                if (!div_by_zero || quotient !== {WIDTH{1'b1}} || remainder !== dv) begin
                    errors=errors+1;
                    $display("FAIL(unsigned div0) dv=%0d ds=%0d got q=%h r=%h dbz=%b",
                              dv, ds, quotient, remainder, div_by_zero);
                end
            end else if (quotient !== exp_q || remainder !== exp_r) begin
                errors=errors+1;
                $display("FAIL(unsigned) dv=%0d ds=%0d got q=%0d r=%0d exp q=%0d r=%0d",
                          dv, ds, quotient, remainder, exp_q, exp_r);
            end
            @(posedge clk);
        end
    endtask
 
    integer i;
    reg signed [WIDTH-1:0] rd, rs;
    initial begin
        $dumpfile("sim/div_wave.vcd");
        $dumpvars(0, div_tb);
        rst_n=0; start=0; a=0; b=0; signed_mode=0;
        #12 rst_n=1;
 
        $display("--- directed signed cases ---");
        run_signed(13,3);
        run_signed(13,-3);
        run_signed(-13,3);
        run_signed(-13,-3);
        run_signed(7,2);
        run_signed(-7,2);
        run_signed(7,-2);
        run_signed(-7,-2);
        run_signed(0,5);
        run_signed(6,3);
        run_signed(-6,3);
        run_signed(5,0);                       // signed div by zero
 
        $display("--- INT_MIN edge cases (signed) ---");
        run_signed(-32'sd2147483648, 1);        // INT_MIN / 1
        run_signed(-32'sd2147483648, -1);       // INT_MIN / -1 (classic overflow case too)
        run_signed(-32'sd2147483648, 2);        // INT_MIN / 2
        run_signed(-32'sd2147483648, -32'sd2147483648); // INT_MIN / INT_MIN
        run_signed(1, -32'sd2147483648);        // 1 / INT_MIN
        run_signed(-1, -32'sd2147483648);       // -1 / INT_MIN
        run_signed(32'sd2147483647, -32'sd2147483648); // MAX / INT_MIN
 
        $display("--- directed unsigned cases ---");
        run_unsigned(13,3);
        run_unsigned(0,5);
        run_unsigned(32'hFFFFFFFF, 1);
        run_unsigned(32'hFFFFFFFF, 32'hFFFFFFFF);
        run_unsigned(5,0);
        run_unsigned(32'h80000000, 2);
 
        $display("--- random signed ---");
        for (i=0;i<500;i=i+1) begin
            rd = $random; rs = $random;
            run_signed(rd, rs);
        end
 
        $display("--- random unsigned ---");
        for (i=0;i<300;i=i+1) begin
            rd = $random; rs = $random;
            run_unsigned(rd, rs);
        end
 
        if (errors==0) $display("ALL %0d TESTS PASSED", tests);
        else $display("%0d / %0d TESTS FAILED", errors, tests);
        $finish;
    end
endmodule
