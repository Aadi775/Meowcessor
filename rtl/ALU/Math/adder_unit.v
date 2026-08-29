module adder_unit #(
    parameter WIDTH = 32
)(
    input                    clk,
    input                    rst_n,
    input                    start,
    input      [WIDTH-1:0]   rs1_data,
    input      [WIDTH-1:0]   rs2_data,
    output reg [WIDTH-1:0]   result,
    output reg               done,
    output                   busy
);

    reg [WIDTH-1:0] a_reg;
    reg [WIDTH-1:0] b_reg;
    reg             running;

    wire [WIDTH-1:0] sum;
    wire             carry_out;

    Add #(.WIDTH(WIDTH)) adder (
        .a   (a_reg),
        .b   (b_reg),
        .Cin (1'b0),
        .sum (sum),
        .Cout(carry_out)
    );

    assign busy = running;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_reg   <= {WIDTH{1'b0}};
            b_reg   <= {WIDTH{1'b0}};
            running <= 1'b0;
            done    <= 1'b0;
            result  <= {WIDTH{1'b0}};
        end else begin
            done <= 1'b0;

            if (start && !running) begin
                a_reg   <= rs1_data;
                b_reg   <= rs2_data;
                running <= 1'b1;
            end else if (running) begin
                result  <= sum;
                done    <= 1'b1;
                running <= 1'b0;
            end
        end
    end

endmodule