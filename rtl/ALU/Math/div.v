module radix4_srt_divider #(
    parameter WIDTH = 32
)(
    input                    clk,
    input                    rst_n,
    input                    start,
    input                    signed_mode,
    input      [WIDTH-1:0]   rs1_data,
    input      [WIDTH-1:0]   rs2_data,
    output reg [WIDTH-1:0]   quotient,
    output reg [WIDTH-1:0]   remainder,
    output reg               done,
    output                   busy,
    output reg               div_by_zero
);

    localparam MAG_WIDTH   = WIDTH + 1;
    localparam SCAN_WIDTH  = MAG_WIDTH + (MAG_WIDTH % 2);
    localparam STEPS       = SCAN_WIDTH / 2;
    localparam STEP_WIDTH  = $clog2(STEPS + 1);
    localparam ACC_WIDTH   = MAG_WIDTH + 3;

    reg [WIDTH-1:0]            dividend_abs;
    reg [WIDTH-1:0]            divisor_abs;
    reg [SCAN_WIDTH-1:0]       dividend_scan;
    reg [WIDTH-1:0]            quotient_work;
    reg [ACC_WIDTH-1:0]        remainder_work;
    reg [STEP_WIDTH-1:0]       step_index;
    reg                        running;
    reg                        quotient_neg;
    reg                        remainder_neg;

    assign busy = running;

    // ---- abs(rs1_data) via Add: 0 + ~rs1_data + 1 = -rs1_data ----
    wire [WIDTH-1:0] rs1_neg_sum;
    Add #(.WIDTH(WIDTH)) neg_rs1 (
        .a({WIDTH{1'b0}}), .b(~rs1_data), .Cin(1'b1), .sum(rs1_neg_sum), .Cout()
    );
    wire [WIDTH-1:0] rs1_abs_val = rs1_data[WIDTH-1] ? rs1_neg_sum : rs1_data;

    // ---- abs(rs2_data) via Add ----
    wire [WIDTH-1:0] rs2_neg_sum;
    Add #(.WIDTH(WIDTH)) neg_rs2 (
        .a({WIDTH{1'b0}}), .b(~rs2_data), .Cin(1'b1), .sum(rs2_neg_sum), .Cout()
    );
    wire [WIDTH-1:0] rs2_abs_val = rs2_data[WIDTH-1] ? rs2_neg_sum : rs2_data;

    wire [WIDTH-1:0] dividend_abs_selected = signed_mode ? rs1_abs_val : rs1_data;
    wire [WIDTH-1:0] divisor_abs_selected  = signed_mode ? rs2_abs_val : rs2_data;

    wire [ACC_WIDTH-1:0] divisor_ext = {3'b000, divisor_abs};

    // ---- divisor_x2: pure shift, no adder needed ----
    wire [ACC_WIDTH-1:0] divisor_x2 = divisor_ext << 1;

    // ---- divisor_x3 = divisor_ext + divisor_x2, via Add ----
    wire [ACC_WIDTH-1:0] divisor_x3;
    Add #(.WIDTH(ACC_WIDTH), .STAGES(7)) divisor_x3_adder (
        .a(divisor_ext), .b(divisor_x2), .Cin(1'b0), .sum(divisor_x3), .Cout()
    );

    wire [STEP_WIDTH-1:0] step_minus_one = step_index - 1'b1;
    wire [1:0] current_pair = dividend_scan[(step_minus_one * 2) +: 2];
    wire [ACC_WIDTH-1:0] shifted_remainder = (remainder_work << 2) | current_pair;

    wire [1:0] q_digit = (shifted_remainder >= divisor_x3) ? 2'd3 :
                         (shifted_remainder >= divisor_x2) ? 2'd2 :
                         (shifted_remainder >= divisor_ext) ? 2'd1 : 2'd0;

    wire [ACC_WIDTH-1:0] q_term = (q_digit == 2'd3) ? divisor_x3 :
                                  (q_digit == 2'd2) ? divisor_x2 :
                                  (q_digit == 2'd1) ? divisor_ext : {ACC_WIDTH{1'b0}};

    // ---- remainder_next = shifted_remainder - q_term, via Add ----
    wire [ACC_WIDTH-1:0] remainder_next;
    Add #(.WIDTH(ACC_WIDTH), .STAGES(7)) remainder_sub (
        .a(shifted_remainder), .b(~q_term), .Cin(1'b1), .sum(remainder_next), .Cout()
    );

    wire [WIDTH-1:0] quotient_next = (quotient_work << 2) | q_digit;

    // ---- final negation of quotient/remainder, via Add ----
    wire [WIDTH-1:0] quotient_next_neg;
    Add #(.WIDTH(WIDTH)) neg_quotient (
        .a({WIDTH{1'b0}}), .b(~quotient_next), .Cin(1'b1), .sum(quotient_next_neg), .Cout()
    );

    wire [WIDTH-1:0] remainder_next_low_neg;
    Add #(.WIDTH(WIDTH)) neg_remainder (
        .a({WIDTH{1'b0}}), .b(~remainder_next[WIDTH-1:0]), .Cin(1'b1), .sum(remainder_next_low_neg), .Cout()
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dividend_abs  <= {WIDTH{1'b0}};
            divisor_abs   <= {WIDTH{1'b0}};
            dividend_scan <= {SCAN_WIDTH{1'b0}};
            quotient_work <= {WIDTH{1'b0}};
            remainder_work <= {ACC_WIDTH{1'b0}};
            step_index    <= {STEP_WIDTH{1'b0}};
            running       <= 1'b0;
            quotient_neg  <= 1'b0;
            remainder_neg <= 1'b0;
            quotient      <= {WIDTH{1'b0}};
            remainder     <= {WIDTH{1'b0}};
            done          <= 1'b0;
            div_by_zero   <= 1'b0;
        end else begin
            done <= 1'b0;

            if (start && !running) begin
                dividend_abs  <= dividend_abs_selected;
                divisor_abs   <= divisor_abs_selected;
                dividend_scan <= {{(SCAN_WIDTH-WIDTH){1'b0}}, dividend_abs_selected};
                quotient_work <= {WIDTH{1'b0}};
                remainder_work <= {ACC_WIDTH{1'b0}};
                step_index    <= STEPS[STEP_WIDTH-1:0];
                quotient_neg  <= signed_mode && (rs1_data[WIDTH-1] ^ rs2_data[WIDTH-1]);
                remainder_neg <= signed_mode && rs1_data[WIDTH-1];
                div_by_zero   <= 1'b0;

                if (divisor_abs_selected == {WIDTH{1'b0}}) begin
                    quotient    <= {WIDTH{1'b1}};
                    remainder   <= rs1_data;
                    done        <= 1'b1;
                    div_by_zero <= 1'b1;
                    running     <= 1'b0;
                end else begin
                    running <= 1'b1;
                end
            end else if (running) begin
                if (step_index == 1) begin
                    running <= 1'b0;
                    done    <= 1'b1;

                    quotient  <= quotient_neg ? quotient_next_neg : quotient_next;
                    remainder <= remainder_neg ? remainder_next_low_neg : remainder_next[WIDTH-1:0];
                end else begin
                    quotient_work <= quotient_next;
                    remainder_work <= remainder_next;
                    step_index    <= step_index - 1'b1;
                end
            end
        end
    end

endmodule