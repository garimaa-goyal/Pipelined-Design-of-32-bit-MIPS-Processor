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
  
  parameter RR_ALU = 3'b000, RM_ALU = 3'b001, LOAD = 3'b010, STORE = 3'b011, BRANCH = 3'b100, HALT = 3'b101;
  reg HALTED; // set after HLT instruction is completed in WB stage
  reg TAKEN_BRANCH; // set if branch is to be taken
  
  always @(posedge clk1) // Instruction Fetch stage
    begin
      if(HALTED == 0)
        begin
          if(((EX_MEM_IR[31:26] == BEQZ) && (EX_MEM_COND == 1)) || ((EX_MEM_IR[31:26] == BNEQZ) && (EX_MEM_COND == 0)))
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
  
  always @(posedge clk2)  // ID stage--> getting rs, rt, immediate and decoding
    begin
      if(HALTED == 0) 
        begin
          if(IF_ID_IR[25:21] == 5'b00000) begin  ID_EX_A <= 0; end
          else begin ID_EX_A <= #2 REG[IF_ID_IR[25:21]] ; end //rs- source register
          
          if(IF_ID_IR[20:16] == 5'b00000) begin ID_EX_B <= 0; end
          else begin ID_EX_B <= #2 REG[IF_ID_IR[20:16]] ; end //rt- second source register
          
          ID_EX_NPC <= #2 IF_ID_NPC;
          ID_EX_IR <= #2 IF_ID_IR;
          ID_EX_IMM <= #2 {{16{IF_ID_IR[15]}}, {IF_ID_IR[15:0]}}; // setting ID_EX_IMM VALUE WITH SIGN EXTENSION
          
          case(IF_ID_IR[31:26])
            ADD, SUB, AND, OR, MUL, SLT: ID_EX_TYPE <=  #2 RR_ALU;
            ADDI, SUBI, SLTI:            ID_EX_TYPE <= #2 RM_ALU;
            LW:							 ID_EX_TYPE <= #2 LOAD;
            SW: 						 ID_EX_TYPE <= #2 STORE;
            BNEQZ, BEQZ:				 ID_EX_TYPE <= #2 BRANCH;
            HLT: 						 ID_EX_TYPE <= #2 HALT;
            default:                     ID_EX_TYPE <= #2 HALT;                    // invalid opcode
           endcase
          end
    end
  
  always @ (posedge clk1) // EX STAGE
    begin
      if(HALTED == 0)
        begin
          EX_MEM_TYPE <= #2 ID_EX_TYPE;
          EX_MEM_IR  <= #2 ID_EX_IR;
          TAKEN_BRANCH <= #2 1'b0;
          
          case(ID_EX_TYPE) // BASED ON TYPE WHETHER RR_ALU, RM_ALU, BRANCH ETC.
            RR_ALU: begin
              case(ID_EX_IR[31:26]) //OPCODE
                ADD: EX_MEM_ALUOUT <= #2 ID_EX_A + ID_EX_B;
                SUB: EX_MEM_ALUOUT <= #2 ID_EX_A - ID_EX_B;
                MUL: EX_MEM_ALUOUT <= #2 ID_EX_A * ID_EX_B;
                AND: EX_MEM_ALUOUT <= #2 ID_EX_A & ID_EX_B;
                OR:  EX_MEM_ALUOUT <= #2 ID_EX_A | ID_EX_B;
                SLT: EX_MEM_ALUOUT <= #2 ID_EX_A < ID_EX_B;
                default: EX_MEM_ALUOUT <= #2 32'hx;
              endcase
            end
            RM_ALU: begin
              case(ID_EX_IR[31:26]) //OPCODE
                ADDI: EX_MEM_ALUOUT <= #2 ID_EX_A + ID_EX_IMM;
                SUBI: EX_MEM_ALUOUT <= #2 ID_EX_A - ID_EX_IMM;
                SLTI: EX_MEM_ALUOUT <= #2 ID_EX_A * ID_EX_IMM;
                default: EX_MEM_ALUOUT <= #2 32'hx;
              endcase
            end
            LOAD, STORE: begin
              EX_MEM_ALUOUT<= #2 ID_EX_A + ID_EX_IMM; // address is calculated and stored in EX_MEM_ALUOUT
              EX_MEM_B <= #2 ID_EX_B; // value of B is forwarded to next stage for store operation
            end
            
            BRANCH: begin
              EX_MEM_ALUOUT <= #2 ID_EX_NPC + ID_EX_IMM;
              EX_MEM_COND <= #2 (ID_EX_A ==0);
            end
          endcase
        end
    end
  
  always @ (posedge clk2)// MEM STAGE
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
            STORE: if(TAKEN_BRANCH == 0)
              MEM[EX_MEM_ALUOUT] <= #2 EX_MEM_B; // STORING THE VALUE OF B INTO MEMORY AT ADDRESS "EX_MEM_ALUOUT", we forwarded this value in EX stage for storing purpose only
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
            
          
                
              
              
              
      
          
