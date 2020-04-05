module rv (
  output reg [2:0] leds
);
  reg clk; 
  reg reset; 
  wire [31:0] daddr;
  wire [31:0] dout;
  reg [31:0] din;
  wire drw; 

  reg [31:0] iin;

  wire [31:0] iaddr;

  reg [31:0] imem [0:1023];
  reg [31:0] dmem [0:1023];
  
  rv_core cpu(clk, reset, daddr, dout, din, drw, iaddr, iin);

  always @(posedge clk) begin
    iin <= imem[iaddr[11:2]];
  end

  always @(posedge clk) begin
    din <= dmem[daddr[11:2]];

    if (drw) begin
      $display("Top write to %x <= %x", daddr, dout);
      dmem[daddr[11:2]] <= dout;
      if (daddr[12] == 1'b1)
        leds[2:0] <= dout[2:0];
    end
    else begin
      $display("Top read from %x => %x", daddr, din);
    end
  end

  initial begin
    $dumpfile("rv.vcd");
    $dumpvars(0,rv);
    $readmemh("t2b.hex", imem);
    $display("go!");
    reset = 1;
    #20
    reset = 0;
  end

  always begin
    clk= 1; #5; 
    // $display("TB: iaddr = %8x", iaddr);
    clk= 0; #5;
  end
endmodule

module rv_core (
  input         clk,
  input         reset,

  output reg [31:0] daddr,
  output reg [31:0] dout,
  input      [31:0] din,
  output reg        drw,

  output reg [31:0] iaddr,
  input      [31:0] iin
);

  // internals
  reg [31:0] rv5_pc;
  reg [31:0] rv5_nextpc;
  reg [31:0] rv5_pc4;
  reg [31:0] rv5_reg[0:31];
  reg [31:0] rv5_opcode;

  // decode
  wire [6:0] op;
  assign op = rv5_opcode[6:0];

  wire [31:0] U_immediate;
  assign U_immediate = { 12'b0, rv5_opcode[31:12] };

  wire [31:0] J_immediate_SE;
  assign J_immediate_SE = { {12{rv5_opcode[31]}}, rv5_opcode[19:12], rv5_opcode[20], rv5_opcode[30:21], 1'b0 };

  wire [31:0] B_immediate_SE; 
  assign B_immediate_SE = { {20{rv5_opcode[31]}}, rv5_opcode[7], rv5_opcode[30:25], rv5_opcode[11:8], 1'b0 };

  wire [31:0] I_immediate_SE; 
  assign I_immediate_SE = { {21{rv5_opcode[31]}}, rv5_opcode[30:20] };

  wire [31:0] S_immediate_SE; 
  assign S_immediate_SE = { {21{rv5_opcode[31]}}, rv5_opcode[30:25], rv5_opcode[11:7] };

  wire [6:0] funct7;
  assign funct7 = rv5_opcode[31:25];

  wire [2:0] funct3;
  assign funct3 = rv5_opcode[14:12];

  wire [4:0] rd;
  assign rd = rv5_opcode[11:7];

  wire [4:0] rs1;
  assign rs1 = rv5_opcode[19:15];

  wire [4:0] rs2;
  assign rs2 = rv5_opcode[24:20];

  wire [4:0] shamt;
  assign shamt = rs2;

  reg jal;
  reg jalr;
  reg branch;
  reg exception;

  reg mem;
  reg wb;
  reg [31:0] alures;

  // CPU state machine

  parameter P_RESET = 0;
  parameter P_FETCH = 1;
  parameter P_DECODE = 2;
  parameter P_EXECUTE = 3;
  parameter P_MEMORY = 4;
  parameter P_WRITEBACK = 5;

  reg[2:0] state, next_state;

  always @(posedge(clk)) state <= next_state;

  always @(posedge(clk)) begin
    if (reset) next_state = P_RESET; 
    else case (state)
      P_RESET: begin
        $display("In reset");
        rv5_pc <= 32'h0;         // RESET PC = 0
        rv5_reg[0] <= 32'h0;     // R0 always 0
        rv5_reg[2] <= 32'h1000;  // R2 is SP
        rv5_reg[8] <= 32'hf00dface;  // R8 is FP

        daddr <= 32'hdeadaffe;
        dout  <= 32'hcafebabe;
        mem <= 0;
        next_state <= P_FETCH;
      end

      P_FETCH: begin
        $display("----------------");
        iaddr <= rv5_pc;

        mem <= 0;
        wb <= 0;
        branch <= 0;
        jal <= 0;
        jalr <= 0;
        drw <= 0;
        daddr <= 0;

        next_state <= P_DECODE;
      end

      P_DECODE: begin
        rv5_opcode <= iin;
        rv5_pc4 <= rv5_pc + 4;
        $display("fetch: opcode @ %08x = %08x", rv5_pc, rv5_opcode);
        next_state <= P_EXECUTE;
      end

      P_EXECUTE: begin
        $display("In execute");

        case (op)
          7'b0110111: begin wb <= 1; alures <= U_immediate << 12; $display("LUI "); end
          7'b0010111: begin wb <= 1; alures <= (U_immediate << 12) + rv5_pc; $display("AUIPC "); end
          7'b1101111: begin wb <= 1; jal <= 1; rv5_nextpc <= J_immediate_SE + rv5_pc; alures <= rv5_pc + 32'h4; $display("JAL pc=%x + imm=%x ", rv5_pc, J_immediate_SE); end
          7'b1100111: begin wb <= 1; jalr <= 1; rv5_nextpc <= (I_immediate_SE + rv5_reg[rs1]) & 32'hFFFFFFFE; alures <= rv5_pc + 32'h4; $display("JALR R%d=%x + imm=%x ", rs1, rv5_reg[rs1], I_immediate_SE); end
          7'b1100011: begin
                      wb <= 1;
                      rv5_nextpc <= B_immediate_SE + rv5_pc;
                      $display("B nextpc = %x", rv5_nextpc);
                      case (funct3)
                        3'b000: begin if (rv5_reg[rs1]==rv5_reg[rs2]) branch <= 1; $display("BEQ "); end
                        3'b001: begin if (rv5_reg[rs1]!=rv5_reg[rs2]) branch <= 1; $display("BNE "); end
                        3'b100: begin if ($signed(rv5_reg[rs1])< $signed(rv5_reg[rs2])) branch <= 1; $display("BLT "); end
                        3'b101: begin if ($signed(rv5_reg[rs1])>=$signed(rv5_reg[rs2])) branch <= 1; $display("BGE "); end
                        3'b110: begin if (rv5_reg[rs1]< rv5_reg[rs2]) branch <= 1; $display("BLTU "); end
                        3'b111: begin if (rv5_reg[rs1]>=rv5_reg[rs2]) branch <= 1; $display("BGEU "); end
                        default: exception <= 1;
                      endcase
                      end
          7'b0000011: begin
                      mem <= 1;
                      wb <= 1;
                      case (funct3)
                        3'b000: begin daddr <= I_immediate_SE+rv5_reg[rs1]; drw <= 1'b0; $display("LB "); end
                        3'b001: begin daddr <= I_immediate_SE+rv5_reg[rs1]; drw <= 1'b0; $display("LH "); end
                        3'b010: begin daddr <= I_immediate_SE+rv5_reg[rs1]; drw <= 1'b0; $display("LW from %x + %x", I_immediate_SE, rv5_reg[rs1]); end
                        3'b100: begin daddr <= I_immediate_SE+rv5_reg[rs1]; drw <= 1'b0; $display("LBU "); end
                        3'b101: begin daddr <= I_immediate_SE+rv5_reg[rs1]; drw <= 1'b0; $display("LWU "); end
                        default: exception <= 1;
                      endcase
                      end
          7'b0100011: begin
                      mem <= 1;
                      wb <= 0;
                      case (funct3)
                        3'b000: begin daddr <= S_immediate_SE+rv5_reg[rs1]; dout <= rv5_reg[rs2]; drw <= 1'b1; $display("SB "); end
                        3'b001: begin daddr <= S_immediate_SE+rv5_reg[rs1]; dout <= rv5_reg[rs2]; drw <= 1'b1; $display("SH "); end
                        3'b010: begin daddr <= S_immediate_SE+rv5_reg[rs1]; dout <= rv5_reg[rs2]; drw <= 1'b1; $display("SW to %x = %x + %x <= %x", S_immediate_SE+rv5_reg[rs1], S_immediate_SE, rv5_reg[rs1], rv5_reg[rs2]); end
                        default: exception <= 1;
                      endcase
                      end
          7'b0010011: begin
                      wb <= 1;
                      case (funct3)
                        3'b000: begin alures <= I_immediate_SE + rv5_reg[rs1]; $display("ADDI %x + (R%d=)%x = %x", I_immediate_SE, rs1, rv5_reg[rs1], alures); end
                        3'b001: begin 
                          case (funct7)
                            7'b0000000: begin alures <= (rv5_reg[rs1] << shamt); $display("SLLI "); end
                            default: exception <= 1;
                          endcase
                          end
                        3'b010: begin alures <= $signed(rv5_reg[rs1]) < $signed(I_immediate_SE) ? 32'h1 : 32'h0; $display("SLT "); end
                        3'b011: begin alures <= rv5_reg[rs1] < I_immediate_SE ? 32'h1 : 32'h0; $display("SLTIU "); end
                        3'b100: begin alures <= rv5_reg[rs1] ^ I_immediate_SE; $display("XORI "); end
                        3'b101: begin 
                          case (funct7)
                            7'b0100000: begin alures <= rv5_reg[rs1] >>> shamt; $display("SRAI "); end
                            7'b0000000: begin alures <= rv5_reg[rs1] >> shamt; $display("SRLI "); end
                            default: exception <= 1;
                          endcase
                          end
                        3'b110: begin alures <= rv5_reg[rs1] | I_immediate_SE; $display("ORI "); end
                        3'b111: begin alures <= rv5_reg[rs1] & I_immediate_SE; $display("ANDI "); end
                        default: exception <= 1;
                      endcase
                      end 
          7'b0110011: begin
                      wb <= 1;
                      case (funct3)
                        3'b000: begin if (funct7 == 7'b0100000) begin alures <= rv5_reg[rs1] - rv5_reg[rs2]; $display("SUB "); end
                                                           else begin alures <= rv5_reg[rs1] + rv5_reg[rs2]; $display("ADD "); end
                                end
                        3'b001: begin alures <= rv5_reg[rs1] << (rv5_reg[rs2] & 32'h1F); $display("SLL "); end
                        3'b010: begin alures <= $signed(rv5_reg[rs1]) < $signed(rv5_reg[rs2]) ? 32'h1 : 32'h0; $display("SLT "); end
                        3'b011: begin alures <= rv5_reg[rs1] < rv5_reg[rs2] ? 32'h1 : 32'h0; $display("SLTU "); end
                        3'b100: begin alures <= rv5_reg[rs1] ^ rv5_reg[rs2]; $display("XOR "); end
                        3'b101: begin
                          case (funct7)
                            7'b0100000: begin alures <= rv5_reg[rs1] >>> (rv5_reg[rs2] & 32'h1F); $display("SRA "); end
                            7'b0000000: begin alures <= rv5_reg[rs1] >> (rv5_reg[rs2] & 32'h1F); $display("SRL "); end
                            default: exception <= 1;
                          endcase
                          end
                        3'b110: begin alures <= rv5_reg[rs1] | rv5_reg[rs2]; $display("OR "); end
                        3'b111: begin alures <= rv5_reg[rs1] & rv5_reg[rs2]; $display("AND "); end
                        default: exception <= 1;
                      endcase
                      end 
          default: begin
                     wb <= 0;
                     $display("unknown opcode!");
                   end 
        endcase

        next_state <= P_MEMORY;
      end

      P_MEMORY: begin
        if (mem == 1) begin
          $display("In memory pc=%x", rv5_pc);
          if (drw == 0) begin wb <= 1; alures <= din; $display("memory read:  %x (%x) = %x", drw, daddr, alures); end
          if (drw == 1) $display("memory write: %x (%x) = %x", drw, daddr, dout);
          $display("R0  =      %x", rv5_reg[0]);
          $display("R1  = RA = %x", rv5_reg[1]);
          $display("R2  = SP = %x", rv5_reg[2]);
          $display("R8  = S0 = %x", rv5_reg[8]);
          $display("R14 = A4 = %x", rv5_reg[14]);
          $display("R15 = A5 = %x", rv5_reg[15]);
        end
        next_state <= P_WRITEBACK;
      end

      P_WRITEBACK: begin
        $display("In writeback pc=%x", rv5_pc);
        if (exception == 1) begin
          rv5_pc = 32'h0888; // exception vector
        end 
        else if (jal == 1) begin
          rv5_pc = rv5_nextpc;
        end 
        else if (jalr == 1) begin
          rv5_pc = rv5_nextpc;
        end 
        else if (branch == 1) begin
          rv5_pc = rv5_nextpc;
        end
        else begin
          rv5_pc = rv5_pc4;
        end

        if (wb == 1) begin
          if (rd != 0) rv5_reg[rd] <= alures;
          rv5_reg[0] <= 0;

          $display("wb: R%x <= %x", rd, alures);
          $display("R0  =      %x", rv5_reg[0]);
          $display("R1  = RA = %x", rv5_reg[1]);
          $display("R2  = SP = %x", rv5_reg[2]);
          $display("R8  = S0 = %x", rv5_reg[8]);
          $display("R14 = A4 = %x", rv5_reg[14]);
          $display("R15 = A5 = %x", rv5_reg[15]);
        end

        next_state <= P_FETCH;
      end

      default: begin
        $display("In default, undef");
        next_state <= P_RESET;
      end

    endcase
  end

endmodule

