`include "defines.v"

module decoder(
    input  wire [31:0] inst,

    // Register file indices
    output wire [4:0] rs1_addr,
    output wire [4:0] rs2_addr,
    output wire [4:0] rd_addr,

    // Control signals
    output reg        reg_we,
    output reg  [1:0] alu_src_a,  // 00: rs1, 01: PC, 10: Zero
    output reg        alu_src_b,  // 0: rs2, 1: imm
    output reg  [4:0] alu_op,
    output reg        mem_we,
    output reg        mem_re,
    output reg        branch,
    output reg        jump,
    output reg        jalr,
    output reg  [1:0] wb_sel,     // 00: ALU, 01: Mem, 10: PC+4, 11: CSR

    // CSR specific
    output reg        csr_we,
    output reg        csr_re,

    // Exceptions
    output reg        illegal_inst
);

    wire [6:0] opcode = inst[6:0];
    wire [2:0] funct3 = inst[14:12];
    wire [6:0] funct7 = inst[31:25];

    assign rs1_addr = inst[19:15];
    assign rs2_addr = inst[24:20];
    assign rd_addr  = inst[11:7];

    always @(*) begin
        // Default values
        reg_we       = 1'b0;
        alu_src_a    = 2'b00; // rs1
        alu_src_b    = 1'b0;  // rs2
        alu_op       = `ALU_OP_ADD;
        mem_we       = 1'b0;
        mem_re       = 1'b0;
        branch       = 1'b0;
        jump         = 1'b0;
        jalr         = 1'b0;
        wb_sel       = 2'b00; // ALU
        csr_we       = 1'b0;
        csr_re       = 1'b0;
        illegal_inst = 1'b0;

        case (opcode)
            `OP_LUI: begin
                reg_we    = 1'b1;
                alu_src_a = 2'b10; // Zero
                alu_src_b = 1'b1;  // Imm
                alu_op    = `ALU_OP_ADD;
                wb_sel    = 2'b00; // ALU
            end

            `OP_AUIPC: begin
                reg_we    = 1'b1;
                alu_src_a = 2'b01; // PC
                alu_src_b = 1'b1;  // Imm
                alu_op    = `ALU_OP_ADD;
                wb_sel    = 2'b00; // ALU
            end

            `OP_JAL: begin
                reg_we    = 1'b1;
                jump      = 1'b1;
                wb_sel    = 2'b10; // PC + 4
            end

            `OP_JALR: begin
                if (funct3 == 3'b000) begin
                    reg_we    = 1'b1;
                    jump      = 1'b1;
                    jalr      = 1'b1;
                    wb_sel    = 2'b10; // PC + 4
                end else begin
                    illegal_inst = 1'b1;
                end
            end

            `OP_BRANCH: begin
                branch    = 1'b1;
                alu_src_a = 2'b00; // rs1
                alu_src_b = 1'b0;  // rs2
                case (funct3)
                    `FUNCT3_BEQ, `FUNCT3_BNE: alu_op = `ALU_OP_SUB;
                    `FUNCT3_BLT, `FUNCT3_BGE: alu_op = `ALU_OP_SLT;
                    `FUNCT3_BLTU, `FUNCT3_BGEU: alu_op = `ALU_OP_SLTU;
                    default: illegal_inst = 1'b1;
                endcase
            end

            `OP_LOAD: begin
                reg_we    = 1'b1;
                alu_src_a = 2'b00; // rs1
                alu_src_b = 1'b1;  // Imm
                alu_op    = `ALU_OP_ADD;
                mem_re    = 1'b1;
                wb_sel    = 2'b01; // Mem
                if (funct3 == 3'b011 || funct3 == 3'b110 || funct3 == 3'b111) begin
                    illegal_inst = 1'b1;
                end
            end

            `OP_STORE: begin
                alu_src_a = 2'b00; // rs1
                alu_src_b = 1'b1;  // Imm
                alu_op    = `ALU_OP_ADD;
                mem_we    = 1'b1;
                if (funct3 > 3'b010) begin
                    illegal_inst = 1'b1;
                end
            end

            `OP_OP_IMM: begin
                reg_we    = 1'b1;
                alu_src_a = 2'b00; // rs1
                alu_src_b = 1'b1;  // Imm
                wb_sel    = 2'b00; // ALU

                case (funct3)
                    `FUNCT3_ADD_SUB: alu_op = `ALU_OP_ADD;
                    `FUNCT3_SLL:     begin
                        alu_op = `ALU_OP_SLL;
                        if (funct7 != 7'b0000000) illegal_inst = 1'b1;
                    end
                    `FUNCT3_SLT:     alu_op = `ALU_OP_SLT;
                    `FUNCT3_SLTU:    alu_op = `ALU_OP_SLTU;
                    `FUNCT3_XOR:     alu_op = `ALU_OP_XOR;
                    `FUNCT3_SRL_SRA: begin
                        if (funct7 == `FUNCT7_ZERO) alu_op = `ALU_OP_SRL;
                        else if (funct7 == `FUNCT7_SUB) alu_op = `ALU_OP_SRA;
                        else illegal_inst = 1'b1;
                    end
                    `FUNCT3_OR:      alu_op = `ALU_OP_OR;
                    `FUNCT3_AND:     alu_op = `ALU_OP_AND;
                endcase
            end

            `OP_OP: begin
                reg_we    = 1'b1;
                alu_src_a = 2'b00; // rs1
                alu_src_b = 1'b0;  // rs2
                wb_sel    = 2'b00; // ALU

                if (funct7 == `FUNCT7_MULDIV) begin
                    case (funct3)
                        `FUNCT3_MUL:    alu_op = `ALU_OP_MUL;
                        `FUNCT3_MULH:   alu_op = `ALU_OP_MULH;
                        `FUNCT3_MULHSU: alu_op = `ALU_OP_MULHSU;
                        `FUNCT3_MULHU:  alu_op = `ALU_OP_MULHU;
                        `FUNCT3_DIV:    alu_op = `ALU_OP_DIV;
                        `FUNCT3_DIVU:   alu_op = `ALU_OP_DIVU;
                        `FUNCT3_REM:    alu_op = `ALU_OP_REM;
                        `FUNCT3_REMU:   alu_op = `ALU_OP_REMU;
                        default:        illegal_inst = 1'b1;
                    endcase
                end else begin
                    case (funct3)
                        `FUNCT3_ADD_SUB: alu_op = (funct7 == `FUNCT7_SUB) ? `ALU_OP_SUB : `ALU_OP_ADD;
                        `FUNCT3_SLL:     alu_op = `ALU_OP_SLL;
                        `FUNCT3_SLT:     alu_op = `ALU_OP_SLT;
                        `FUNCT3_SLTU:    alu_op = `ALU_OP_SLTU;
                        `FUNCT3_XOR:     alu_op = `ALU_OP_XOR;
                        `FUNCT3_SRL_SRA: alu_op = (funct7 == `FUNCT7_SUB) ? `ALU_OP_SRA : `ALU_OP_SRL;
                        `FUNCT3_OR:      alu_op = `ALU_OP_OR;
                        `FUNCT3_AND:     alu_op = `ALU_OP_AND;
                    endcase
                    if (funct7 != `FUNCT7_ZERO && funct7 != `FUNCT7_SUB) illegal_inst = 1'b1;
                end
            end

            `OP_MISC_MEM: begin
                // FENCE, FENCE.I
                if (funct3 != 3'b000 && funct3 != 3'b001) begin
                    illegal_inst = 1'b1;
                end
            end

            `OP_SYSTEM: begin
                if (funct3 == 3'b000) begin
                    // ECALL (0x00000073) / EBREAK (0x00100073)
                    if (inst[31:20] != 12'b000000000000 && inst[31:20] != 12'b000000000001) begin
                        illegal_inst = 1'b1;
                    end
                end else begin
                    // CSR Instructions
                    csr_re = 1'b1;
                    reg_we = 1'b1;
                    wb_sel = 2'b11; // CSR

                    if (funct3 == 3'b001 || funct3 == 3'b101) begin
                        // CSRRW, CSRRWI
                        csr_we = 1'b1;
                    end else if (funct3 == 3'b010 || funct3 == 3'b011 || funct3 == 3'b110 || funct3 == 3'b111) begin
                        // CSRRS, CSRRC, CSRRSI, CSRRCI
                        csr_we = (rs1_addr != 5'b0);
                    end else begin
                        illegal_inst = 1'b1;
                        csr_re = 1'b0;
                        reg_we = 1'b0;
                    end
                end
            end

            default: begin
                illegal_inst = 1'b1;
            end
        endcase
    end

endmodule
