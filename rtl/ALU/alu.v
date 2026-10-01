//`include "defines.v"
// ============================================================================
//  Meowcessor ALU — Top-Level Arithmetic/Logic Unit Wrapper
// ============================================================================
//
//  Unified ALU that dispatches to the appropriate functional unit based on
//  a 4-bit ALU_OP code (from defines.v).
//
//  Sub-units:
//    - Kogge-Stone parallel-prefix adder  (ADD, SUB, SLT, SLTU)
//    - Booth radix-4 signed multiplier    (MUL, MULH)
//    - SRT radix-4 signed/unsigned divider (DIV, DIVU, REM, REMU)
//    - Combinational logic & barrel shift  (AND, OR, XOR, SLL, SRL, SRA)
//
//  Interface protocol:
//    - Assert `start` for one cycle with valid `alu_op`, `rs1_data`, `rs2_data`.
//    - For single-cycle ops:  `done` pulses HIGH the next cycle, `busy` = 0.
//    - For multi-cycle ops:   `busy` goes HIGH, `done` pulses when complete.
//    - `result` holds the 32-bit result; `result_hi` holds the upper 32 bits
//      (only meaningful for MULH).
//
// ============================================================================

module alu #(
    parameter WIDTH = 32
)(
    input                    clk,
    input                    rst_n,
    input                    start,
    input      [3:0]         alu_op,
    input      [WIDTH-1:0]   rs1_data,
    input      [WIDTH-1:0]   rs2_data,
    output reg [WIDTH-1:0]   result,
    output reg [WIDTH-1:0]   result_hi,
    output reg               done,
    output                   busy,
    output                   div_by_zero
);

    // ========================================================================
    //  Internal wires & registers
    // ========================================================================

    // Latched operation code for multi-cycle tracking
    reg  [3:0]          op_reg;
    reg                 multicycle_active;

    // --- Kogge-Stone adder I/O ---
    reg  [WIDTH-1:0]    add_a, add_b;
    reg                 add_cin;
    wire [WIDTH-1:0]    add_sum;
    wire                add_cout;

    // --- Booth multiplier I/O ---
    reg                 mul_start;
    wire [2*WIDTH-1:0]  mul_result;
    wire                mul_done;
    wire                mul_busy;

    // --- SRT divider I/O ---
    reg                 div_start;
    wire                div_signed_mode;
    wire [WIDTH-1:0]    div_quotient;
    wire [WIDTH-1:0]    div_remainder;
    wire                div_done;
    wire                div_busy;
    wire                div_dbz;

    // --- Combinational results ---
    reg  [WIDTH-1:0]    logic_result;
    reg  [WIDTH-1:0]    shift_result;

    // --- Single-cycle result staging ---
    reg  [WIDTH-1:0]    single_result;
    reg                 single_valid;

    // ========================================================================
    //  Sub-unit instantiation
    // ========================================================================

    // Kogge-Stone adder (combinational)
    Add #(.WIDTH(WIDTH)) u_adder (
        .a    (add_a),
        .b    (add_b),
        .Cin  (add_cin),
        .sum  (add_sum),
        .Cout (add_cout)
    );

    // Booth radix-4 multiplier (multi-cycle, clocked)
    booth_radix4_multiplier #(.WIDTH(WIDTH)) u_mul (
        .clk      (clk),
        .rst_n    (rst_n),
        .start    (mul_start),
        .rs1_data (rs1_data),
        .rs2_data (rs2_data),
        .result   (mul_result),
        .done     (mul_done),
        .busy     (mul_busy)
    );

    // SRT radix-4 divider (multi-cycle, clocked)
    radix4_srt_divider #(.WIDTH(WIDTH)) u_div (
        .clk         (clk),
        .rst_n       (rst_n),
        .start       (div_start),
        .signed_mode (div_signed_mode),
        .rs1_data    (rs1_data),
        .rs2_data    (rs2_data),
        .quotient    (div_quotient),
        .remainder   (div_remainder),
        .done        (div_done),
        .busy        (div_busy),
        .div_by_zero (div_dbz)
    );

    // ========================================================================
    //  Combinational logic: adder input muxing
    // ========================================================================
    //
    //  ADD:  a + b + 0
    //  SUB:  a + ~b + 1   (two's complement subtraction via Kogge-Stone)
    //  SLT:  a + ~b + 1   (subtract, then check sign of result)
    //  SLTU: a + ~b + 1   (subtract, then check carry-out)
    //

    always @(*) begin
        case (alu_op)
            `ALU_OP_SUB,
            `ALU_OP_SLT,
            `ALU_OP_SLTU: begin
                add_a   = rs1_data;
                add_b   = ~rs2_data;
                add_cin = 1'b1;
            end
            default: begin
                // ADD and all other ops that don't use the adder
                add_a   = rs1_data;
                add_b   = rs2_data;
                add_cin = 1'b0;
            end
        endcase
    end

    // ========================================================================
    //  Combinational logic: bitwise operations
    // ========================================================================

    always @(*) begin
        case (alu_op)
            `ALU_OP_AND: logic_result = rs1_data & rs2_data;
            `ALU_OP_OR:  logic_result = rs1_data | rs2_data;
            `ALU_OP_XOR: logic_result = rs1_data ^ rs2_data;
            default:     logic_result = {WIDTH{1'b0}};
        endcase
    end

    // ========================================================================
    //  Combinational logic: shift operations
    // ========================================================================
    //
    //  SLL: logical left shift
    //  SRL: logical right shift
    //  SRA: arithmetic right shift (sign-extended)
    //

    wire [4:0] shamt = rs2_data[4:0];

    always @(*) begin
        case (alu_op)
            `ALU_OP_SLL: shift_result = rs1_data << shamt;
            `ALU_OP_SRL: shift_result = rs1_data >> shamt;
            `ALU_OP_SRA: shift_result = $signed(rs1_data) >>> shamt;
            default:     shift_result = {WIDTH{1'b0}};
        endcase
    end

    // ========================================================================
    //  Combinational logic: single-cycle result MUX
    // ========================================================================

    always @(*) begin
        case (alu_op)
            `ALU_OP_ADD:  single_result = add_sum;
            `ALU_OP_SUB:  single_result = add_sum;
            `ALU_OP_AND:  single_result = logic_result;
            `ALU_OP_OR:   single_result = logic_result;
            `ALU_OP_XOR:  single_result = logic_result;
            `ALU_OP_SLL:  single_result = shift_result;
            `ALU_OP_SRL:  single_result = shift_result;
            `ALU_OP_SRA:  single_result = shift_result;
            `ALU_OP_SLT: begin
                // Signed comparison via subtraction:
                // If operands have different signs, the negative one is less.
                // If operands have same sign, check the sign of (a - b).
                single_result = {
                    {(WIDTH-1){1'b0}},
                    (rs1_data[WIDTH-1] ^ rs2_data[WIDTH-1])
                        ? rs1_data[WIDTH-1]     // different signs: a<0 means a < b
                        : add_sum[WIDTH-1]       // same sign: sub result sign
                };
            end
            `ALU_OP_SLTU: begin
                // Unsigned comparison: a < b <==> (a - b) borrows <==> no carry-out
                single_result = {{(WIDTH-1){1'b0}}, ~add_cout};
            end
            default: single_result = {WIDTH{1'b0}};
        endcase
    end

    // ========================================================================
    //  Classify operation: single-cycle vs multi-cycle
    // ========================================================================

    wire is_mul_op = (alu_op == `ALU_OP_MUL) || (alu_op == `ALU_OP_MULH);
    wire is_div_op = (alu_op == `ALU_OP_DIV)  || (alu_op == `ALU_OP_DIVU) ||
                     (alu_op == `ALU_OP_REM)  || (alu_op == `ALU_OP_REMU);
    wire is_multicycle = is_mul_op || is_div_op;

    // ========================================================================
    //  Multi-cycle dispatch: registered start pulses for sub-units
    // ========================================================================
    //
    //  To avoid delta-cycle races between the ALU FSM and the sub-unit FSMs
    //  on the same posedge, we use a two-phase approach:
    //    Phase 1 (cycle N):   start=1 → ALU latches op, sets launch_mul/launch_div
    //    Phase 2 (cycle N+1): registered mul_start/div_start fires → sub-unit starts
    //

    reg launch_mul;
    reg launch_div;
    reg launch_div_signed;

    // div_signed_mode must be stable when the divider samples it
    assign div_signed_mode = launch_div_signed;

    assign busy         = multicycle_active;
    assign div_by_zero  = div_dbz;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            result            <= {WIDTH{1'b0}};
            result_hi         <= {WIDTH{1'b0}};
            done              <= 1'b0;
            op_reg            <= 4'd0;
            multicycle_active <= 1'b0;
            mul_start         <= 1'b0;
            div_start         <= 1'b0;
            launch_mul        <= 1'b0;
            launch_div        <= 1'b0;
            launch_div_signed <= 1'b0;
        end else begin
            done      <= 1'b0;  // default: done is a single-cycle pulse
            mul_start <= 1'b0;  // default: start pulses are one-cycle
            div_start <= 1'b0;

            // --- Phase 2: fire the registered start pulse ---
            if (launch_mul) begin
                mul_start  <= 1'b1;
                launch_mul <= 1'b0;
            end
            if (launch_div) begin
                div_start         <= 1'b1;
                launch_div        <= 1'b0;
            end

            // --- Phase 1: accept new operation ---
            if (start && !multicycle_active) begin
                if (is_multicycle) begin
                    // Multi-cycle: latch the operation and schedule sub-unit start
                    op_reg            <= alu_op;
                    multicycle_active <= 1'b1;

                    if (is_mul_op) begin
                        launch_mul <= 1'b1;
                    end
                    if (is_div_op) begin
                        launch_div        <= 1'b1;
                        launch_div_signed <= (alu_op == `ALU_OP_DIV) || (alu_op == `ALU_OP_REM);
                    end
                end else begin
                    // Single-cycle: capture result immediately
                    result    <= single_result;
                    result_hi <= {WIDTH{1'b0}};
                    done      <= 1'b1;
                end
            end

            // --- Multiplier completion ---
            if (multicycle_active && mul_done) begin
                case (op_reg)
                    `ALU_OP_MUL: begin
                        result    <= mul_result[WIDTH-1:0];
                        result_hi <= {WIDTH{1'b0}};
                    end
                    `ALU_OP_MULH: begin
                        result    <= mul_result[WIDTH-1:0];
                        result_hi <= mul_result[2*WIDTH-1:WIDTH];
                    end
                    default: begin
                        result    <= {WIDTH{1'b0}};
                        result_hi <= {WIDTH{1'b0}};
                    end
                endcase
                done              <= 1'b1;
                multicycle_active <= 1'b0;
            end

            // --- Divider completion ---
            if (multicycle_active && div_done) begin
                case (op_reg)
                    `ALU_OP_DIV,
                    `ALU_OP_DIVU: begin
                        result <= div_quotient;
                    end
                    `ALU_OP_REM,
                    `ALU_OP_REMU: begin
                        result <= div_remainder;
                    end
                    default: begin
                        result <= {WIDTH{1'b0}};
                    end
                endcase
                result_hi         <= {WIDTH{1'b0}};
                done              <= 1'b1;
                multicycle_active <= 1'b0;
            end
        end
    end

endmodule
