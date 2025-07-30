// Code your design here
// Code your design here
// Code your design here
// Code your design here
module pipe_MIPS32(clk1, clk2);
  input clk1, clk2; // two phase clock
  reg[31:0] IF_ID_IR, IF_ID_NPC, PC;
  reg[31:0] ID_EX_IR, ID_EX_NPC, ID_EX_A, ID_EX_B, ID_EX_IMM;
  reg[2:0] ID_EX_TYPE, EX_MEM_TYPE, MEM_WB_TYPE; // type means whether it is R_R ALU or R-M ALU operation etc,.
  reg[31:0] EX_MEM_IR, EX_MEM_ALUOUT, EX_MEM_B, EX_MEM_COND;
  reg[31:0] MEM_WB_IR, MEM_WB_ALUOUT, MEM_WB_LMD;
  
  reg[31:0] REG[0:31]; // register bank 32*32
  reg[31:0] MEM[0:1023]; // memory 1024*32
  parameter ADD = 6'b000000, SUB = 6'b000001, AND = 6'b000010, OR = 6'b000011, SLT = 6'b000100, MUL = 6'b000101, HLT = 6'b111111, LW = 6'b001000, SW = 6'b001001, ADDI = 6'b001010, SUBI = 6'b001011, SLTI = 6'b001100, BNEQZ = 6'b001101,
  BEQZ = 6'b001110;
  
  parameter RR_ALU = 3'b000, RM_ALU = 3'b001, LOAD = 3'b010, STORE = 3'b011, BRANCH = 3'b100, HALT = 3'b101,NOP_T=3'b110;  // added bubble/NOP type
  
  reg HALTED; // set after HLT instruction is completed in WB stage
  reg TAKEN_BRANCH; // set if branch is to be taken
  // --- ADD THIS INITIAL BLOCK ---
initial begin
  // Architectural state
  PC           = 32'd0;
  HALTED       = 1'b0;
  TAKEN_BRANCH = 1'b0;

  // IF/ID
  IF_ID_IR     = 32'd0;
  IF_ID_NPC    = 32'd0;

  // ID/EX
  ID_EX_IR     = 32'd0;
  ID_EX_NPC    = 32'd0;
  ID_EX_A      = 32'd0;
  ID_EX_B      = 32'd0;
  ID_EX_IMM    = 32'd0;
  ID_EX_TYPE   = NOP_T;

  // EX/MEM
  EX_MEM_IR     = 32'd0;
  EX_MEM_ALUOUT = 32'd0;
  EX_MEM_B      = 32'd0;
  EX_MEM_COND   = 1'b0;   // suggest making EX_MEM_COND 1-bit
  EX_MEM_TYPE   = NOP_T;

  // MEM/WB
  MEM_WB_IR     = 32'd0;
  MEM_WB_ALUOUT = 32'd0;
  MEM_WB_LMD    = 32'd0;
  MEM_WB_TYPE   = NOP_T;
end

  
  // ---------- NEW: hazard/forwarding wires ----------
  wire isLoad_IDEX = (ID_EX_TYPE == LOAD);
  wire isload_EXMEM = (EX_MEM_TYPE == LOAD);
  wire wbIsLoad = (MEM_WB_TYPE == LOAD);
  wire wbIsAlu = (MEM_WB_TYPE == RR_ALU)|| (MEM_WB_TYPE == RM_ALU);
  
  // Destination register decodes for each stage
  wire[4:0] dest_IDEX = (ID_EX_TYPE == RR_ALU)?ID_EX_IR[15:11]: ((ID_EX_TYPE == RM_ALU)||(ID_EX_TYPE == LOAD))?ID_EX_IR[20:16]: 5'b00000;
  
  wire[4:0] dest_EXMEM = (EX_MEM_TYPE == RR_ALU)? EX_MEM_IR[15:11] : ((EX_MEM_TYPE == RM_ALU)|| (EX_MEM_TYPE == LOAD))? EX_MEM_IR[20:16] : 5'b00000;
  
  wire[4:0] dest_MEMWB = (MEM_WB_TYPE == RR_ALU)? MEM_WB_IR[15:11] : ((MEM_WB_TYPE == RM_ALU) || (MEM_WB_TYPE == LOAD))? MEM_WB_IR[20:16] : 5'b00000;
  
  // Source register decodes for IF/ID (needed for load-use check)
  
  wire[4:0] ifid_rs = IF_ID_IR[25:21];
  wire[4:0] ifid_rt = IF_ID_IR[20:16];
   // ---------- NEW: Load-Use Hazard Detection ----------
  // If an instruction in EX is a LOAD, and the instruction in ID uses that loaded register as a source,
  // we must stall for one cycle.
  
  reg STALL;
  always @(*) begin
     // By default: no stall
    STALL = 1'b0;
     // Only check when not halted and IF/ID has a valid instruction (avoid X-propagation)
    if(HALTED == 1'b0) begin
      if(isLoad_IDEX) begin 
        if((dest_IDEX != 5'b00000) && ((dest_IDEX == ifid_rs)||(dest_IDEX == ifid_rt))) 
          begin
            STALL = 1'b1;
          end 
      end
    end
  end
  
  // -------------Instruction Fetch stage---------------------
  
  always @(posedge clk1) 
    begin
      if(HALTED == 0)
        begin
          if(STALL) begin 
           // NEW: hold PC and IF/ID on load-use hazard
            PC <= #2 PC;
            IF_ID_IR <= #2 IF_ID_IR;
            IF_ID_NPC <= #2 IF_ID_NPC;
          end
          
          else if(((EX_MEM_IR[31:26] == BEQZ) && (EX_MEM_COND == 1)) || ((EX_MEM_IR[31:26] == BNEQZ) && (EX_MEM_COND == 0)))
            begin
              IF_ID_IR <= #2 MEM[EX_MEM_ALUOUT];
              TAKEN_BRANCH <= #2 1'b1;
              IF_ID_NPC <= #2 EX_MEM_ALUOUT+1;
              PC <= #2 EX_MEM_ALUOUT+1;
            end
          else
            begin
              IF_ID_IR <= #2 MEM[PC];
              IF_ID_NPC <= #2 PC+1;
              PC <= #2 PC+1;
            end
        end
    end
  
  //-------------------------------------------------------------------------------
  // ----------- ID stage--> getting rs, rt, immediate and decoding---------------
  always @(posedge clk2)  
    begin
      if(HALTED == 0) 
        begin
          if(IF_ID_IR[25:21] == 5'b00000) begin  ID_EX_A <= 0; end
          else begin ID_EX_A <= #2 REG[IF_ID_IR[25:21]] ; end //rs- source register
          
          if(IF_ID_IR[20:16] == 5'b00000) begin ID_EX_B <= 0; end
          else begin ID_EX_B <= #2 REG[IF_ID_IR[20:16]] ; end //rt- second source register
          
          ID_EX_NPC <= #2 IF_ID_NPC;
          
          if(STALL) begin //------inject a bubble into EX on stall ----------
            ID_EX_IR <= #2 32'b0;
            ID_EX_IMM <= #2 32'b0;
            ID_EX_TYPE <= #2 NOP_T;
          end else begin
          ID_EX_IR <= #2 IF_ID_IR;
          ID_EX_IMM <= #2 {{16{IF_ID_IR[15]}}, {IF_ID_IR[15:0]}}; // setting ID_EX_IMM VALUE WITH SIGN EXTENSION
          
          case(IF_ID_IR[31:26])
            ADD, SUB, AND, OR, MUL, SLT: ID_EX_TYPE <=  #2 RR_ALU;
            ADDI, SUBI, SLTI:            ID_EX_TYPE <= #2 RM_ALU;
            LW:							 ID_EX_TYPE <= #2 LOAD;
            SW: 						 ID_EX_TYPE <= #2 STORE;
            BNEQZ, BEQZ:				 ID_EX_TYPE <= #2 BRANCH;
            HLT: 						 ID_EX_TYPE <= #2 HALT;
            default:                     ID_EX_TYPE <= #2 NOP_T;                    // invalid opcode
           endcase
          end
        end
    end
  // ------------------EX: Execute / Address calc / Branch eval with FORWARDING ----------
   reg[31:0] Ain, Bin;
   reg[31:0] fwd_wb_value;
  always @ (posedge clk1) 
    begin
      if(HALTED == 0)
        begin
          EX_MEM_TYPE <= #2 ID_EX_TYPE;
          EX_MEM_IR  <= #2 ID_EX_IR;
          TAKEN_BRANCH <= #2 1'b0;
        // FOrwarding logic 
         
          //value available at WB  (could be ALUOUT or LMD for Loads)
          fwd_wb_value = (wbIsLoad) ? MEM_WB_LMD: (wbIsAlu)? MEM_WB_ALUOUT: 32'hx;
          // A input (rs)
          if((EX_MEM_TYPE == RR_ALU || EX_MEM_TYPE == RM_ALU) && dest_EXMEM != 5'b00000 && dest_EXMEM == ID_EX_IR[25:21])
            begin
              Ain = EX_MEM_ALUOUT;
            end
          else if ((wbIsLoad || wbIsAlu) && dest_MEMWB != 5'b00000 && dest_MEMWB == ID_EX_IR[25:21]) begin 
            Ain = fwd_wb_value;
          end 
          else begin
            Ain = ID_EX_A;
          end
          ////////-------B input (rt)----------------
          if((EX_MEM_TYPE == RR_ALU || EX_MEM_TYPE == RM_ALU) && dest_EXMEM != 5'b00000 && dest_EXMEM == ID_EX_IR[20:16])
            begin
              Bin = EX_MEM_ALUOUT;
            end
          else if ((wbIsLoad || wbIsAlu) && dest_MEMWB != 5'b00000 && dest_MEMWB == ID_EX_IR[20:16]) begin
            Bin = fwd_wb_value;
          end
          else begin
            Bin = ID_EX_B;
          end
          
          case(ID_EX_TYPE) // BASED ON TYPE WHETHER RR_ALU, RM_ALU, BRANCH ETC.
            NOP_T: begin
              EX_MEM_ALUOUT <= #2 32'b0;
              EX_MEM_B <= #2 32'b0;
              EX_MEM_COND <= #2 1'b0;
            end
            RR_ALU: begin
              case(ID_EX_IR[31:26]) //OPCODE
                ADD: EX_MEM_ALUOUT <= #2 Ain + Bin;
                SUB: EX_MEM_ALUOUT <= #2 Ain - Bin;
                MUL: EX_MEM_ALUOUT <= #2 Ain * Bin;
                AND: EX_MEM_ALUOUT <= #2 Ain & Bin;
                OR:  EX_MEM_ALUOUT <= #2 Ain | Bin;
                SLT: EX_MEM_ALUOUT <= #2 Ain < Bin;
                default: EX_MEM_ALUOUT <= #2 32'hx;
              endcase
            end
            RM_ALU: begin
              case(ID_EX_IR[31:26]) //OPCODE
                ADDI: EX_MEM_ALUOUT <= #2 Ain + ID_EX_IMM;
                SUBI: EX_MEM_ALUOUT <= #2 Ain - ID_EX_IMM;
                SLTI: EX_MEM_ALUOUT <= #2 Ain * ID_EX_IMM;
                default: EX_MEM_ALUOUT <= #2 32'hx;
              endcase
            end
            LOAD, STORE: begin
          // Address calc uses forwarded Ain
              EX_MEM_ALUOUT<= #2 Ain + ID_EX_IMM; // address is calculated and stored in EX_MEM_ALUOUT
              // ---------- NEW: forward store data (Bin) for SW ----------
          // Ensure stores see most recent value
              EX_MEM_B <= #2 Bin; // value of B is forwarded to next stage for store operation
            end
            
            BRANCH: begin
              EX_MEM_ALUOUT <= #2 ID_EX_NPC + ID_EX_IMM;
              EX_MEM_COND <= #2 (Ain ==0);
            end
            default: begin 
              EX_MEM_ALUOUT <= 32'hx;
            end
          endcase
        end
    end
  /////-----------MEM STAGE-------------
  always @ (posedge clk2)
    begin
      if(HALTED == 0)
        begin
          MEM_WB_TYPE <= #2 EX_MEM_TYPE; // TYPE IS FORWARDED
          MEM_WB_IR <= #2 EX_MEM_IR; // IR IS FORWARDED
          
          case(EX_MEM_TYPE)
            RR_ALU, RM_ALU:
              MEM_WB_ALUOUT <= #2 EX_MEM_ALUOUT; // RESULT OF ALUOUT IS FORWARDED
            LOAD:
              MEM_WB_LMD <= #2 MEM[EX_MEM_ALUOUT]; // LOAD LMD REG WITH VALUE STORED AT EX_MEM_ALUOUT
            STORE: begin 
              if(TAKEN_BRANCH == 0) begin 
              MEM[EX_MEM_ALUOUT] <= #2 EX_MEM_B; // STORING THE VALUE OF B INTO MEMORY AT ADDRESS "EX_MEM_ALUOUT", we forwarded this value in EX stage for storing purpose only
              end
            end
          endcase
        end
    end
  
  always @ (posedge clk1)
    begin
      if(TAKEN_BRANCH == 0)  // disable write if branch is taken
        begin
          case(MEM_WB_TYPE)
            RR_ALU : REG[MEM_WB_IR[15:11]] <= #2 MEM_WB_ALUOUT; //write result in destination reg
            RM_ALU : REG[MEM_WB_IR[20:16]] <= #2 MEM_WB_ALUOUT;
            LOAD:    REG[MEM_WB_IR[20:16]] <= #2 MEM_WB_LMD;
            HALT:    HALTED                <= #2 1'b1;
          endcase
        end
    end
endmodule
          
