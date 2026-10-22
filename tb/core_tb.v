`timescale 1ns/1ps

module core_tb;

    reg clk;
    reg rst_n;

    // Core memory interfaces
    wire [31:0] imem_addr;
    wire [31:0] imem_rdata;

    wire [31:0] dmem_addr;
    wire [31:0] dmem_wdata;
    wire [3:0]  dmem_wstrb;
    wire        dmem_we;
    wire        dmem_re;
    wire [31:0] dmem_rdata;

    cpu_core u_core(
        .clk(clk),
        .rst_n(rst_n),
        .imem_addr(imem_addr),
        .imem_rdata(imem_rdata),
        .dmem_addr(dmem_addr),
        .dmem_wdata(dmem_wdata),
        .dmem_wstrb(dmem_wstrb),
        .dmem_we(dmem_we),
        .dmem_re(dmem_re),
        .dmem_rdata(dmem_rdata)
    );

    // Instruction Memory Mock
    reg [31:0] imem [0:63];
    assign imem_rdata = imem[imem_addr >> 2]; // PC is byte-addressed, array is word-addressed

    // Data Memory Mock
    reg [7:0] dmem [0:1023];
    wire [9:0] dmem_word_addr = {dmem_addr[9:2], 2'b00};
    assign dmem_rdata = {dmem[dmem_word_addr + 3], dmem[dmem_word_addr + 2],
                         dmem[dmem_word_addr + 1], dmem[dmem_word_addr]};

    always @(posedge clk) begin
        if (dmem_we) begin
            if (dmem_wstrb[0]) dmem[dmem_word_addr]     <= dmem_wdata[7:0];
            if (dmem_wstrb[1]) dmem[dmem_word_addr + 1] <= dmem_wdata[15:8];
            if (dmem_wstrb[2]) dmem[dmem_word_addr + 2] <= dmem_wdata[23:16];
            if (dmem_wstrb[3]) dmem[dmem_word_addr + 3] <= dmem_wdata[31:24];
        end
    end

    function [31:0] enc_i;
        input [11:0] imm;
        input [4:0] rs1;
        input [2:0] funct3;
        input [4:0] rd;
        input [6:0] opcode;
        begin enc_i = {imm, rs1, funct3, rd, opcode}; end
    endfunction

    function [31:0] enc_s;
        input [11:0] imm;
        input [4:0] rs2;
        input [4:0] rs1;
        input [2:0] funct3;
        input [6:0] opcode;
        begin enc_s = {imm[11:5], rs2, rs1, funct3, imm[4:0], opcode}; end
    endfunction

    // Clock gen
    always #5 clk = ~clk;

    initial begin
        $dumpfile("core_tb.vcd");
        $dumpvars(0, core_tb);

        // A short program exercises every aligned RV32I data width.
        // Data begins at byte address 0x100.
        imem[0]  = enc_i(12'h100, 0, 3'b000, 1, 7'b0010011); // ADDI x1,x0,256
        imem[1]  = enc_i(12'hfff, 0, 3'b000, 2, 7'b0010011); // ADDI x2,x0,-1
        imem[2]  = enc_s(12'd0, 2, 1, 3'b010, 7'b0100011);   // SW x2,0(x1)
        imem[3]  = enc_i(12'd0, 1, 3'b000, 3, 7'b0000011);   // LB x3,0(x1)
        imem[4]  = enc_i(12'd0, 1, 3'b100, 4, 7'b0000011);   // LBU x4,0(x1)
        imem[5]  = enc_i(12'd0, 1, 3'b001, 5, 7'b0000011);   // LH x5,0(x1)
        imem[6]  = enc_i(12'd0, 1, 3'b101, 6, 7'b0000011);   // LHU x6,0(x1)
        imem[7]  = enc_i(12'd0, 1, 3'b010, 7, 7'b0000011);   // LW x7,0(x1)
        imem[8]  = enc_i(12'h012, 0, 3'b000, 8, 7'b0010011); // ADDI x8,x0,18
        imem[9]  = enc_s(12'd1, 8, 1, 3'b000, 7'b0100011);   // SB x8,1(x1)
        imem[10] = enc_i(12'd1, 1, 3'b000, 9, 7'b0000011);   // LB x9,1(x1)
        imem[11] = enc_i(12'd0, 1, 3'b001, 10, 7'b0000011);  // LH x10,0(x1)
        imem[12] = enc_s(12'd2, 2, 1, 3'b001, 7'b0100011);   // SH x2,2(x1)
        imem[13] = enc_i(12'd0, 1, 3'b010, 11, 7'b0000011);  // LW x11,0(x1)
        imem[14] = 32'b0;

        clk = 0;
        rst_n = 0;

        for (integer i = 0; i < 64; i = i + 1) begin
            if (i > 14) imem[i] = 32'b0;
        end
        for (integer j = 0; j < 1024; j = j + 1) dmem[j] = 8'b0;

        #15 rst_n = 1;

        fork
            begin
                wait (imem_addr == 32'd56);
                #1;
                if (u_core.u_regfile.regs[3] !== 32'hffff_ffff) $fatal(1, "LB sign extension failed");
                if (u_core.u_regfile.regs[4] !== 32'h0000_00ff) $fatal(1, "LBU zero extension failed");
                if (u_core.u_regfile.regs[5] !== 32'hffff_ffff) $fatal(1, "LH sign extension failed");
                if (u_core.u_regfile.regs[6] !== 32'h0000_ffff) $fatal(1, "LHU zero extension failed");
                if (u_core.u_regfile.regs[7] !== 32'hffff_ffff) $fatal(1, "LW failed");
                if (u_core.u_regfile.regs[9] !== 32'h0000_0012) $fatal(1, "LB nonzero lane failed");
                if (u_core.u_regfile.regs[10] !== 32'h0000_12ff) $fatal(1, "LH after SB failed");
                if (u_core.u_regfile.regs[11] !== 32'hffff_12ff) $fatal(1, "LW after SH failed");
                if ({dmem[259], dmem[258], dmem[257], dmem[256]} !== 32'hffff_12ff)
                    $fatal(1, "SB/SH byte-lane writes failed");
                $display("PASS: aligned byte, halfword, and word memory operations");
                $finish;
            end
            begin
                #4000;
                $fatal(1, "Core test timed out at PC=%h", imem_addr);
            end
        join

        $finish;
    end

endmodule
