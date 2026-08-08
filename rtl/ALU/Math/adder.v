
module black_cell(
    input  g_current, p_current,
    input  g_previous, p_previous,
    output g_out, p_out
);
    assign g_out = g_current | (p_current & g_previous);
    assign p_out = p_current & p_previous;
endmodule
 
module grey_cell(
    input g_current, p_current,
    input g_previous,
    output g_out
);
    assign g_out = g_current | (p_current & g_previous);
endmodule
 
module Add #(
    parameter WIDTH  = 32,
    parameter STAGES = 6
)(
    input  [WIDTH-1:0] a,
    input  [WIDTH-1:0] b,
    input  Cin,
    output [WIDTH-1:0] sum,
    output Cout
);
    wire Overflow;
    wire [WIDTH-1:0] p_matrix [0:STAGES-1];
    wire [WIDTH-1:0] g_matrix [0:STAGES-1];
 
    assign p_matrix[0] = a ^ b;
    assign g_matrix[0] = a & b;
 
    genvar stage, i;
    generate
        for (stage = 1; stage < STAGES; stage = stage + 1) begin : stages
            localparam integer SPAN = 1 << (stage-1);
            for (i = 0; i < WIDTH; i = i + 1) begin : bits
                if (i < SPAN) begin
                    assign p_matrix[stage][i] = p_matrix[stage-1][i];
                    assign g_matrix[stage][i] = g_matrix[stage-1][i];
                end else begin
                    black_cell bc(
                        .g_current(g_matrix[stage-1][i]),
                        .p_current(p_matrix[stage-1][i]),
                        .g_previous(g_matrix[stage-1][i-SPAN]),
                        .p_previous(p_matrix[stage-1][i-SPAN]),
                        .g_out(g_matrix[stage][i]),
                        .p_out(p_matrix[stage][i])
                    );
                end
            end
        end
    endgenerate
 
    wire [WIDTH:0] carry;
    assign carry[0] = Cin;
    genvar k;
    generate
        for (k = 0; k < WIDTH; k = k + 1) begin : carry_bits
            assign carry[k+1] = g_matrix[STAGES-1][k] | (p_matrix[STAGES-1][k] & carry[0]);
        end
    endgenerate
 
 
    assign sum  = p_matrix[0] ^ carry[WIDTH-1:0];
    assign Cout = carry[WIDTH];
    assign Overflow = carry[WIDTH-1] ^ carry[WIDTH];
endmodule
