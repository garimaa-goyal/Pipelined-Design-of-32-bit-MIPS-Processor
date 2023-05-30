
//Compute the factorial of number N stored at location 200 and result will be stored at 198 location

module test_mips32;
  reg clk1, clk2;
  integer k;
  pipe_MIPS32 mips(.clk1(clk1),  .clk2(clk2));
  
  initial begin
    clk1 =0; clk2 =0;
    repeat(50) // value here is 50, in other tbs it was 20
      begin
        #5 clk1 = 1; #5 clk2 =0;
        #5 clk1 = 0; #5 clk2 =1;
      end
  end
  
 initial begin
   for(k=0; k<31; k = k+1)
     mips.REG[k] = k;
   
   mips.MEM[0] = 32'h280a00c8;  //ADDI R10, R0,200
   mips.MEM[1] = 32'h28020001; // ADDI R2, R0, 1
   mips.MEM[2] = 32'h0ce77800; // OR R7, R7, R7; dummy instn
   
   mips.MEM[3] = 32'h21430000; //LW R3, 0(R10)
   mips.MEM[4] = 32'h0ce77800; // OR R7, R7, R7; dummy instn
  
   mips.MEM[5] = 32'h14431000; //Loop : MUL R2, R2, R3
   mips.MEM[6] = 32'h2c630001; // SUBI R3, R3,1
   mips.MEM[7] = 32'h0ce77800; // OR R7, R7, R7; dummy instn
   mips.MEM[8] = 32'h3460fffc; //BNEQZ R3, LOOP (-3 is the offset)
   mips.MEM[9] = 32'h2542fffe; // SW R2, -2(R10)
   mips.MEM[10] = 32'hfc000000; //hlt
   
   mips.MEM[200] = 7; // finding factorial of 7
   
  mips.HALTED = 0;
  mips.PC = 0;
  mips. TAKEN_BRANCH =0;
   
   #2000 $display ("values are MEM[200]: %2d\n MEM[198] : %6d", mips.MEM[200], mips.MEM[198]);
 end
  
  
   initial 
     begin
       $dumpfile("waveform.vcd");
     $dumpvars(0,test_mips32);
       $monitor("R2: %4d, R3: %4d", mips.REG[2], mips.REG[3]);
     end
   

    initial begin
     #3000 $finish;
   end
 
   endmodule
   