module booth_radix4_multiplier #(
    parameter WIDTH = 32
)(
    input                    clk,
    input                    rst_n,
    input                    start,
    input                    signed_rs1,
    input                    signed_rs2,
    input      [WIDTH-1:0]   rs1_data,
    input      [WIDTH-1:0]   rs2_data,
    output reg [2*WIDTH-1:0] result,
    output reg               done,
    output                   busy
);

    localparam EXT_WIDTH = WIDTH + 2; // 34 bits for sign/zero extension
    localparam STEPS     = EXT_WIDTH / 2; // 17 steps

    reg [EXT_WIDTH+1:0]           A;
    reg [EXT_WIDTH-1:0]           Q;
    reg                           Q_1;
    reg [EXT_WIDTH-1:0]           M;
    reg [$clog2(STEPS+1)-1:0]     count;
    reg                           running;

    assign busy = running;

    wire [2:0] booth_group = {Q[1], Q[0], Q_1};

    reg [EXT_WIDTH+1:0] operand;
    reg                 op_sub;

    wire [EXT_WIDTH+1:0] M_ext = {{2{M[EXT_WIDTH-1]}}, M};
    wire [EXT_WIDTH+1:0] M_x2  = {M[EXT_WIDTH-1], M, 1'b0};

    always @(*) begin
        case (booth_group)
            3'b000, 3'b111: begin operand = {(EXT_WIDTH+2){1'b0}}; op_sub = 1'b0; end
            3'b001, 3'b010: begin operand = M_ext;                 op_sub = 1'b0; end
            3'b011:         begin operand = M_x2;                  op_sub = 1'b0; end
            3'b100:         begin operand = M_x2;                  op_sub = 1'b1; end
            3'b101, 3'b110: begin operand = M_ext;                 op_sub = 1'b1; end
            default:        begin operand = {(EXT_WIDTH+2){1'b0}}; op_sub = 1'b0; end
        endcase
    end

    wire [EXT_WIDTH+1:0] b_for_add = op_sub ? (~operand) : operand;
    wire                 add_cin   = op_sub;
    wire [EXT_WIDTH+1:0] add_sum;
    wire                 add_cout;

    Add #(.WIDTH(EXT_WIDTH+2), .STAGES(7)) adder (
        .a   (A),
        .b   (b_for_add),
        .Cin (add_cin),
        .sum (add_sum),
        .Cout(add_cout)
    );

    wire [EXT_WIDTH-1:0] rs1_ext = signed_rs1 ? {{2{rs1_data[WIDTH-1]}}, rs1_data} : {2'b00, rs1_data};
    wire [EXT_WIDTH-1:0] rs2_ext = signed_rs2 ? {{2{rs2_data[WIDTH-1]}}, rs2_data} : {2'b00, rs2_data};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            A <= 0; Q <= 0; Q_1 <= 0; M <= 0;
            count <= 0; running <= 1'b0;
            done <= 1'b0; result <= 0;
        end else begin
            done <= 1'b0;

            if (start && !running) begin
                A       <= 0;
                Q       <= rs2_ext;
                Q_1     <= 1'b0;
                M       <= rs1_ext;
                count   <= STEPS;
                running <= 1'b1;
            end else if (running) begin
                if (count == 0) begin
                    running <= 1'b0;
                    done    <= 1'b1;
                    result  <= {A[29:0], Q[33:0]};
                end else begin
                    A     <= {{2{add_sum[EXT_WIDTH+1]}}, add_sum[EXT_WIDTH+1:2]};
                    Q     <= {add_sum[1:0], Q[EXT_WIDTH-1:2]};
                    Q_1   <= Q[1];
                    count <= count - 1'b1;
                end
            end
        end
    end

endmodule