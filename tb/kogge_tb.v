`timescale 1ns/1ps

module tb_Add;
 
    parameter WIDTH  = 32;
    parameter STAGES = 6;
 
    reg  [WIDTH-1:0] a, b;
    reg              Cin;
    wire [WIDTH-1:0] sum;
    wire             Cout;
 
    integer errors = 0;
    integer tests  = 0;
 
    Add #(.WIDTH(WIDTH), .STAGES(STAGES)) dut (
        .a(a), .b(b), .Cin(Cin),
        .sum(sum), .Cout(Cout)
    );
 
    // compares DUT output against a golden {Cout,sum} computed with +
    task check;
        reg [WIDTH:0] expected;
        begin
            tests = tests + 1;
            expected = {1'b0, a} + {1'b0, b} + Cin;
            if ({Cout, sum} !== expected[WIDTH:0]) begin
                errors = errors + 1;
                $display("FAIL  a=%h b=%h Cin=%b | got sum=%h Cout=%b | exp sum=%h Cout=%b",
                          a, b, Cin, sum, Cout, expected[WIDTH-1:0], expected[WIDTH]);
            end
        end
    endtask
 
    integer i;
    reg [WIDTH-1:0] rand_a, rand_b;
    reg rand_cin;
 
    initial begin
        $dumpfile("sim/wave.vcd");
        $dumpvars(0, tb_Add); 
        $display("Starting Kogge-Stone adder testbench (WIDTH=%0d, STAGES=%0d)", WIDTH, STAGES);
         
        

 
        // --- Directed edge cases ---
        a = 0; b = 0; Cin = 0; #1 check;                       // 0 + 0
        a = 0; b = 0; Cin = 1; #1 check;                       // Cin only
        a = {WIDTH{1'b1}}; b = 0; Cin = 0; #1 check;           // all-ones + 0
        a = {WIDTH{1'b1}}; b = 1; Cin = 0; #1 check;           // overflow wraps to 0, Cout=1
        a = {WIDTH{1'b1}}; b = {WIDTH{1'b1}}; Cin = 1; #1 check; // max + max + 1
        a = 32'h0000_0003; b = 32'h0000_0001; Cin = 0; #1 check; // regression case from the bug: 3+1=4
        a = 32'hAAAA_AAAA; b = 32'h5555_5555; Cin = 0; #1 check; // alternating bit patterns
        a = 32'hFFFF_FFFF; b = 32'hFFFF_FFFF; Cin = 0; #1 check;
        a = 32'h8000_0000; b = 32'h8000_0000; Cin = 0; #1 check; // MSB carry only
        a = 32'h0000_0001; b = 32'h0000_0001; Cin = 0; #1 check; // simple carry chain of 1 bit
 
        // --- Carry propagation chain: 0x7FFFFFFF style tests at various widths ---
        for (i = 0; i < WIDTH; i = i + 1) begin
            a = (1 << i) - 1;   // 0..i-1 bits set = ripple carry stress
            b = 1;
            Cin = 0;
            #1 check;
        end
 
        // --- Randomized tests ---
        for (i = 0; i < 2000; i = i + 1) begin
            rand_a   = {$random, $random};
            rand_b   = {$random, $random};
            rand_cin = $random;
            a = rand_a; b = rand_b; Cin = rand_cin;
            #1 check;
        end
 
        if (errors == 0)
            $display("ALL %0d TESTS PASSED", tests);
        else
            $display("%0d / %0d TESTS FAILED", errors, tests);
 
        $finish;
    end
 
endmodule
 
