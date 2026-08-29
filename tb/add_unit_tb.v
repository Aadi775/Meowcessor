`timescale 1ns/1ps

module tb_adder_unit;
    parameter WIDTH = 32;

    reg  clk = 0;
    reg  rst_n;
    reg  start;
    reg  [WIDTH-1:0] a;
    reg  [WIDTH-1:0] b;
    wire [WIDTH-1:0] result;
    wire done;
    wire busy;

    integer errors = 0;
    integer tests  = 0;

    adder_unit #(.WIDTH(WIDTH)) dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .rs1_data(a),
        .rs2_data(b),
        .result(result),
        .done(done),
        .busy(busy)
    );

    always #5 clk = ~clk;

    task run_case;
        input [WIDTH-1:0] av;
        input [WIDTH-1:0] bv;
        reg [WIDTH-1:0] expected;
        begin
            tests = tests + 1;
            a = av;
            b = bv;
            expected = av + bv;

            @(posedge clk);
            start = 1'b1;
            @(posedge clk);
            start = 1'b0;

            wait(done);
            @(posedge clk);

            if (result !== expected) begin
                errors = errors + 1;
                $display("FAIL a=%h b=%h got=%h exp=%h", av, bv, result, expected);
            end
        end
    endtask

    integer i;
    reg [WIDTH-1:0] ra;
    reg [WIDTH-1:0] rb;

    initial begin
        $dumpfile("sim/adder_unit_wave.vcd");
        $dumpvars(0, tb_adder_unit);

        rst_n = 0;
        start = 0;
        a = 0;
        b = 0;
        #12 rst_n = 1;

        run_case(0, 0);
        run_case(1, 1);
        run_case(32'hFFFF_FFFF, 1);
        run_case(32'h8000_0000, 32'h8000_0000);
        run_case(32'hAAAA_AAAA, 32'h5555_5555);

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