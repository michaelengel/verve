module rv (
  output reg [2:0] leds
);

  wire clk;
  wire int_osc;

  reg [27:0]  frequency_counter_i;

  SB_HFOSC  u_SB_HFOSC(.CLKHFPU(1), .CLKHFEN(1), .CLKHF(int_osc));
  
  always @(posedge int_osc) begin
    frequency_counter_i <= frequency_counter_i + 1'b1;
  end
  
  assign clk = frequency_counter_i[18];

  reg [4:0] int_rst_cnt = 0;
  wire reset = int_rst_cnt != 3'b11111;

  always @(posedge clk) begin
    if (int_rst_cnt != 3'b11111)
      int_rst_cnt <= int_rst_cnt + 1;
  end

  wire [31:0] daddr;
  wire [31:0] dout;
  reg  [31:0] din;
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
      dmem[daddr[11:2]] <= dout;
      if (daddr[12] == 1'b1)
        leds[2:0] <= dout[2:0];
    end
  end

  initial begin
    $readmemh("t2a.hex", imem);
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
        next_state <= P_EXECUTE;
      end

      P_EXECUTE: begin
        case (op)
          7'b0110111: begin wb <= 1; alures <= U_immediate << 12; end
          7'b0010111: begin wb <= 1; alures <= (U_immediate << 12) + rv5_pc; end
          7'b1101111: begin wb <= 1; jal <= 1; rv5_nextpc <= J_immediate_SE + rv5_pc; alures <= rv5_pc + 32'h4; end
          7'b1100111: begin wb <= 1; jalr <= 1; rv5_nextpc <= (I_immediate_SE + rv5_reg[rs1]) & 32'hFFFFFFFE; alures <= rv5_pc + 32'h4; end
          7'b1100011: begin
                      wb <= 1;
                      rv5_nextpc <= B_immediate_SE + rv5_pc;
                      case (funct3)
                        3'b000: begin if (rv5_reg[rs1]==rv5_reg[rs2]) branch <= 1;  end
                        3'b001: begin if (rv5_reg[rs1]!=rv5_reg[rs2]) branch <= 1;  end
                        3'b100: begin if (rv5_reg[rs1]< rv5_reg[rs2]) branch <= 1;  end
                        3'b101: begin if (rv5_reg[rs1]>=rv5_reg[rs2]) branch <= 1;  end
                        3'b110: begin if (rv5_reg[rs1]< rv5_reg[rs2]) branch <= 1;  end
                        3'b111: begin if (rv5_reg[rs1]>=rv5_reg[rs2]) branch <= 1;  end
                        default: exception = 1;
                      endcase
                      end
          7'b0000011: begin
                      mem <= 1;
                      wb <= 1;
                      case (funct3)
                        3'b000: begin daddr <= I_immediate_SE+rv5_reg[rs1]; drw <= 1'b0;  end
                        3'b001: begin daddr <= I_immediate_SE+rv5_reg[rs1]; drw <= 1'b0;  end
                        3'b010: begin daddr <= I_immediate_SE+rv5_reg[rs1]; drw <= 1'b0;  end
                        3'b100: begin daddr <= I_immediate_SE+rv5_reg[rs1]; drw <= 1'b0;  end
                        3'b101: begin daddr <= I_immediate_SE+rv5_reg[rs1]; drw <= 1'b0;  end
                      endcase
                      end
          7'b0100011: begin
                      mem <= 1;
                      wb <= 0;
                      case (funct3)
                        3'b000: begin daddr <= S_immediate_SE+rv5_reg[rs1]; dout <= rv5_reg[rs2]; drw <= 1'b1;  end
                        3'b001: begin daddr <= S_immediate_SE+rv5_reg[rs1]; dout <= rv5_reg[rs2]; drw <= 1'b1;  end
                        3'b010: begin daddr <= S_immediate_SE+rv5_reg[rs1]; dout <= rv5_reg[rs2]; drw <= 1'b1;  end
                      endcase
                      end
          7'b0010011: begin
                      wb <= 1;
                      case (funct3)
                        3'b000: begin alures <= I_immediate_SE + rv5_reg[rs1];  end
                        3'b001: begin  end
                        3'b010: begin  end
                        3'b011: begin  end
                        3'b100: begin alures <= rv5_reg[rs1] ^ I_immediate_SE;  end
                        3'b110: begin alures <= rv5_reg[rs1] | I_immediate_SE;  end
                        3'b111: begin alures <= rv5_reg[rs1] & I_immediate_SE;  end
                      endcase
                      end 
          7'b0110011: begin
                      wb <= 1;
                      case (funct3)
                        3'b000: begin if (funct7 == 7'b0100000) begin alures <= rv5_reg[rs1] - rv5_reg[rs2];  end
                                                           else begin alures <= rv5_reg[rs1] + rv5_reg[rs2];  end
                                end
                        3'b001: begin  end
                        3'b010: begin  end
                        3'b011: begin  end
                        3'b100: begin alures <= rv5_reg[rs1] ^ rv5_reg[rs2];  end
                        3'b101: begin  end
                        3'b110: begin alures <= rv5_reg[rs1] | rv5_reg[rs2];  end
                        3'b111: begin alures <= rv5_reg[rs1] & rv5_reg[rs2];  end
                      endcase
                      end 
          default: begin
                     wb <= 0;
                   end 
        endcase

        next_state <= P_MEMORY;
      end

      P_MEMORY: begin
        if (mem == 1) begin
          if (drw == 0) begin alures <= din; wb <= 1;  end
        end
        next_state <= P_WRITEBACK;
      end

      P_WRITEBACK: begin
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

        end

        next_state <= P_FETCH;
      end

      default: begin
        next_state <= P_RESET;
      end

    endcase
  end

endmodule

