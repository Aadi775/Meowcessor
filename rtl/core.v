`include "defines.v"

module cpu_core(
    input clk,
    input rst_n,

    // Instruction Memory Interface
    output [31:0] imem_addr,
    input  [31:0] imem_rdata,

    // Data Memory Interface
    output [31:0] dmem_addr,
    output [31:0] dmem_wdata,
    output [3:0]  dmem_wstrb,
    output        dmem_we,
    output        dmem_re,
    input  [31:0] dmem_rdata
);

    // ========================================================================
    // PC & Instruction Fetch
    // ========================================================================
    reg [31:0] pc;
    assign imem_addr = pc;
    wire [31:0] inst = imem_rdata;

    // ========================================================================
    // Decode Signals
    // ========================================================================
    wire [31:0] imm;
    wire [4:0] rs1_addr, rs2_addr, rd_addr;
    wire reg_we_dec, mem_we_dec, mem_re_dec;
    wire branch, jump, jalr, csr_we, csr_re, illegal_inst;
    wire [1:0] alu_src_a;
    wire alu_src_b;
    wire [4:0] alu_op;
    wire [1:0] wb_sel;

    imm_gen u_imm_gen(
        .inst(inst),
        .imm(imm)
    );

    decoder u_decoder(
        .inst(inst),
        .rs1_addr(rs1_addr), .rs2_addr(rs2_addr), .rd_addr(rd_addr),
        .reg_we(reg_we_dec), .alu_src_a(alu_src_a), .alu_src_b(alu_src_b),
        .alu_op(alu_op), .mem_we(mem_we_dec), .mem_re(mem_re_dec),
        .branch(branch), .jump(jump), .jalr(jalr), .wb_sel(wb_sel),
        .csr_we(csr_we), .csr_re(csr_re), .illegal_inst(illegal_inst)
    );

    // ========================================================================
    // FSM Control
    // ========================================================================
    localparam S_FETCH_DECODE = 1'b0;
    localparam S_WAIT_EXEC    = 1'b1;
    reg state, next_state;

    wire alu_done;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= S_FETCH_DECODE;
        else        state <= next_state;
    end

    always @(*) begin
        next_state = state;
        case (state)
            S_FETCH_DECODE: begin
                // If it's a valid instruction, start execution
                if (inst != 32'b0) next_state = S_WAIT_EXEC;
            end
            S_WAIT_EXEC: begin
                if (alu_done) next_state = S_FETCH_DECODE;
            end
        endcase
    end

    wire alu_start = (state == S_FETCH_DECODE) && (inst != 32'b0);

    // ========================================================================
    // Execution (ALU) & Branching
    // ========================================================================
    wire [31:0] rdata1, rdata2;
    wire [31:0] alu_result, alu_result_hi;
    wire alu_busy, alu_dbz;

    wire [31:0] alu_in_a = (alu_src_a == 2'b00) ? rdata1 :
                           (alu_src_a == 2'b01) ? pc :
                           (alu_src_a == 2'b10) ? 32'b0 : 32'b0;

    wire [31:0] alu_in_b = (alu_src_b == 1'b1) ? imm : rdata2;

    alu u_alu(
        .clk(clk), .rst_n(rst_n), .start(alu_start),
        .alu_op(alu_op), .rs1_data(alu_in_a), .rs2_data(alu_in_b),
        .result(alu_result), .result_hi(alu_result_hi),
        .done(alu_done), .busy(alu_busy), .div_by_zero(alu_dbz)
    );

    wire [2:0] funct3 = inst[14:12];
    reg branch_taken;
    always @(*) begin
        branch_taken = 1'b0;
        if (branch) begin
            case (funct3)
                `FUNCT3_BEQ:  branch_taken = (alu_result == 32'b0);
                `FUNCT3_BNE:  branch_taken = (alu_result != 32'b0);
                `FUNCT3_BLT, `FUNCT3_BLTU: branch_taken = (alu_result == 32'b1);
                `FUNCT3_BGE, `FUNCT3_BGEU: branch_taken = (alu_result == 32'b0);
                default: branch_taken = 1'b0;
            endcase
        end
    end

    // ========================================================================
    // Memory Interface
    // ========================================================================
    wire [31:0] load_data;
    lsu u_lsu(
        .effective_addr(alu_result),
        .funct3(inst[14:12]),
        .store_data(rdata2),
        .memory_rdata(dmem_rdata),
        .memory_addr(dmem_addr),
        .memory_wdata(dmem_wdata),
        .memory_wstrb(dmem_wstrb),
        .load_data(load_data)
    );
    // Perform memory write precisely when ALU finishes addressing (S_WAIT_EXEC cycle)
    assign dmem_we = mem_we_dec & (state == S_WAIT_EXEC) & alu_done;
    assign dmem_re = mem_re_dec & (state == S_WAIT_EXEC) & alu_done;

    // ========================================================================
    // Writeback & Register File
    // ========================================================================
    wire [31:0] csr_rdata = 32'b0; // Mocked for now

    wire [31:0] wdata = (wb_sel == 2'b00) ? alu_result :
                        (wb_sel == 2'b01) ? load_data :
                        (wb_sel == 2'b10) ? (pc + 4) :
                                            csr_rdata;

    // Only write to regfile when execution completes
    wire actual_reg_we = reg_we_dec & (state == S_WAIT_EXEC) & alu_done;

    regfile u_regfile(
        .clk(clk), .rst_n(rst_n),
        .we(actual_reg_we), .waddr(rd_addr), .wdata(wdata),
        .raddr1(rs1_addr), .rdata1(rdata1),
        .raddr2(rs2_addr), .rdata2(rdata2)
    );

    // ========================================================================
    // PC Update
    // ========================================================================
    wire [31:0] next_pc = (jump && !jalr) ? (pc + imm) :
                          (jump && jalr)  ? ((rdata1 + imm) & ~32'd1) :
                          (branch && branch_taken) ? (pc + imm) :
                          (pc + 4);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc <= 32'b0;
        end else if (state == S_WAIT_EXEC && alu_done) begin
            pc <= next_pc;
        end
    end

endmodule
