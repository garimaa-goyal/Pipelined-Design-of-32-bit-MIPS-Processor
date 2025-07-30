`timescale 1ns/1ps

module tb_forwarding;

  // Two-phase clocks
  reg clk1, clk2;

  // DUT
  pipe_MIPS32 dut (.clk1(clk1), .clk2(clk2));

  // -------------------------
  // Local opcodes (must match DUT)
  // -------------------------
  localparam [5:0] ADD  = 6'b000000,
                   SUB  = 6'b000001,
                   AND_ = 6'b000010,
                   OR_  = 6'b000011,
                   SLT  = 6'b000100,
                   MUL  = 6'b000101,
                   HLT  = 6'b111111,
                   LW   = 6'b001000,
                   SW   = 6'b001001,
                   ADDI = 6'b001010,
                   SUBI = 6'b001011,
                   SLTI = 6'b001100,
                   BNEQZ= 6'b001101,
                   BEQZ = 6'b001110;

  // -------------------------
  // Helpers to build instructions
  // -------------------------
  function [31:0] R;
    input [5:0] op;
    input [4:0] rs, rt, rd;
    begin
      // [31:26]=op, [25:21]=rs, [20:16]=rt, [15:11]=rd, [10:0]=0
      R = {op, rs, rt, rd, 11'b0};
    end
  endfunction

  function [31:0] I;
    input [5:0] op;
    input [4:0] rs, rt;
    input [15:0] imm;
    begin
      // [31:26]=op, [25:21]=rs, [20:16]=rt, [15:0]=imm
      I = {op, rs, rt, imm};
    end
  endfunction

  // One "pipeline step": posedge clk1 then posedge clk2
  task step;
    begin
      // clk1 posedge
      #5  clk1 = 1;
      #5  clk1 = 0;
      // clk2 posedge
      #5  clk2 = 1;
      #5  clk2 = 0;
    end
  endtask

  integer i;

  initial begin
    $dumpfile("tb_forwarding.vcd");
    $dumpvars(0, tb_forwarding);

    clk1 = 0;
    clk2 = 0;

    // Clear memories/registers (optional)
    for (i = 0; i < 32; i = i + 1) begin
      dut.REG[i] = 32'd0;
    end
    for (i = 0; i < 1024; i = i + 1) begin
      dut.MEM[i] = 32'd0;
    end

    // -------------------------
    // Initial register values
    // -------------------------
    // r2=10, r3=20  -> r1 should become 30 after ADD
    // r5=5          -> r4 = r1 - r5 = 25 (needs EX/MEM forwarding from r1)
    // r7=3          -> r6 = r1 + r7 = 33 (tests MEM/WB forwarding of r1)
    // r8=100        -> base address for SW/LW tests (we only use SW here)
    dut.REG[2] = 32'd10;
    dut.REG[3] = 32'd20;
    dut.REG[5] = 32'd5;
    dut.REG[7] = 32'd3;
    dut.REG[8] = 32'd100;

    // -------------------------
    // Program (@PC=0)
    // -------------------------
    // 0: ADD  r1, r2, r3        ; r1 = 10 + 20 = 30
    // 1: SUB  r4, r1, r5        ; r4 = 30 - 5 = 25 (EX/MEM -> EX forward)
    // 2: SW   r1, 0(r8)         ; MEM[100] = 30 (forward store data from r1)
    // 3: ADD  r6, r1, r7        ; r6 = 30 + 3 = 33 (MEM/WB -> EX forward)
    // 4: HLT
    dut.MEM[0] = R(ADD , 5'd2, 5'd3, 5'd1);
    dut.MEM[1] = R(SUB , 5'd1, 5'd5, 5'd4);
    dut.MEM[2] = I(SW  , 5'd8, 5'd1, 16'd0);
    dut.MEM[3] = R(ADD , 5'd1, 5'd7, 5'd6);
    dut.MEM[4] = {HLT, 26'd0};

    // -------------------------
    // Run for enough cycles to complete program
    // -------------------------
    // With 5-stage pipeline and 5 instructions, ~10-14 steps is fine.
    for (i = 0; i < 16; i = i + 1) begin
      step();
    end

    // -------------------------
    // Checks
    // -------------------------
    $display("Final REGs: r1=%0d r4=%0d r6=%0d", dut.REG[1], dut.REG[4], dut.REG[6]);
    $display("MEM[100]=%0d", dut.MEM[100]);

    // Expected:
    // r1 = 30 (from ADD)
    // r4 = 25 (SUB uses forwarded r1)
    // r6 = 33 (ADD uses forwarded r1 from MEM/WB)
    // MEM[100] = 30 (SW uses forwarded r1 data)
    if (dut.REG[1]  !== 32'd30) $display("ERROR: r1 expected 30, got %0d", dut.REG[1]);
    if (dut.REG[4]  !== 32'd25) $display("ERROR: r4 expected 25, got %0d", dut.REG[4]);
    if (dut.REG[6]  !== 32'd33) $display("ERROR: r6 expected 33, got %0d", dut.REG[6]);
    if (dut.MEM[100]!== 32'd30) $display("ERROR: MEM[100] expected 30, got %0d", dut.MEM[100]);

    $display("Test complete.");
    $finish;
  end

endmodule
