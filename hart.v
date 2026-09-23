`default_nettype none

// A hart ("hardware thread") is one complete RISC-V CPU: it fetches an
// instruction, decodes it, executes it, and writes the result back. This one
// is single-cycle, so all four of those happen in the same clock cycle and
// exactly one instruction retires every cycle -- there are no bubbles and no
// pipeline stages.
//
// You do not write the datapath blocks again here. Instantiate the four
// modules from phase 2 (`alu`, `rf`, `decoder`, which itself contains `imm`)
// and wire them together, then add the parts phase 2 did not have: the
// program counter, the branch/jump target logic, and the memory interfaces.
//
// Remember the two small changes phase 3 needs from your phase 2 modules:
// `rf` is instantiated with BYPASS_EN = 0 (a single-cycle design writes back
// on the same edge the next read samples, so there is nothing to bypass),
// and `rf` no longer has a write enable -- gate a write by driving its write
// address to 5'd0 instead. Do not instantiate a second copy of `imm`; your
// `decoder` already contains one.
module hart #(
    // The address the program counter is initialized to on reset. The first
    // instruction to retire after `i_rst` deasserts must be the one fetched
    // from this address.
    parameter RESET_ADDR = 32'h00000000
) (
    // Global clock.
    input wire i_clk,
    // Synchronous active-high reset.
    input wire i_rst,

    // ---- Instruction memory ------------------------------------------
    // The instruction memory is external to your design, read-only, and
    // combinational: the word at `o_imem_raddr` appears on `i_imem_rdata`
    // in the same cycle, with no clock edge and no latency.
    //
    // Address of the instruction to fetch. One instruction per cycle,
    // always 4-byte aligned.
    output wire [31:0] o_imem_raddr,
    // The instruction word stored at `o_imem_raddr`.
    input  wire [31:0] i_imem_rdata,

    // ---- Data memory -------------------------------------------------
    // The data memory is also external and combinational: reads need no
    // clock edge, and writes commit on the next clock edge.
    //
    // Data address. This is **always word-aligned** -- the low two bits of
    // the computed byte address never reach memory. Which bytes inside that
    // word are touched is `o_dmem_mask`'s job, not the address's.
    output wire [31:0] o_dmem_addr,
    // Read enable. Must never be high in the same cycle as `o_dmem_wen`.
    output wire        o_dmem_ren,
    // Write enable.
    output wire        o_dmem_wen,
    // Store data. Only the byte lanes selected by `o_dmem_mask` are used;
    // the rest are ignored, so they may hold anything. For a sub-word store
    // (`sb`, `sh`), the byte(s) must be positioned in the lane(s) they are
    // being written to, not left at the bottom of the word.
    output wire [31:0] o_dmem_wdata,
    // Which of the four byte lanes of the word at `o_dmem_addr` are read or
    // written. A byte access asserts one lane, a half-word two adjacent
    // lanes, and a word all four.
    output wire [ 3:0] o_dmem_mask,
    // The full 32-bit word at `o_dmem_addr`, regardless of the mask.
    // Extracting the requested bytes and sign- or zero-extending them
    // (`lb`/`lh` vs `lbu`/`lhu`) is this module's job.
    input  wire [31:0] i_dmem_rdata,

    // ---- Retire interface --------------------------------------------
    // These outputs are not part of RV32I. They exist so a testbench can see
    // what your design actually did each cycle. Drive every one of them
    // appropriately on every cycle; all of them are checked on every
    // retiring instruction.
    //
    // An instruction retired this cycle. Because the design is
    // single-cycle, this is high every cycle after `i_rst` deasserts,
    // through the cycle `o_retire_halt` fires.
    output wire        o_retire_valid,
    // The raw instruction word that was fetched and retired this cycle.
    output wire [31:0] o_retire_inst,
    // The instruction was an illegal encoding, or a misaligned data access
    // (a half-word access at an odd address, or a word access at an address
    // that is not a multiple of four -- a byte access is never misaligned).
    // A trapping instruction has no side effects: no memory access happens,
    // `o_retire_rd_waddr` is 5'd0, and control flow is not redirected
    // (there is no trap vector in this interface, so `o_retire_next_pc` is
    // still the pc plus four).
    output wire        o_retire_trap,
    // The instruction is `ebreak`, and execution should halt. Like a trap,
    // it reads nothing, writes nothing, and touches no memory.
    output wire        o_retire_halt,
    // First source register address, and the value read from it.
    // Instructions that do not read a first source register (`lui`,
    // `auipc`, `jal`, and illegal encodings) must report 5'd0 here.
    output wire [ 4:0] o_retire_rs1_raddr,
    output wire [31:0] o_retire_rs1_rdata,
    // Second source register address, and the value read from it. Only
    // R-type, store and branch instructions read a second source register;
    // everything else must report 5'd0 here.
    output wire [ 4:0] o_retire_rs2_raddr,
    output wire [31:0] o_retire_rs2_rdata,
    // Destination register address, and the value written to it. When the
    // instruction writes no register, this address must be 5'd0 -- the same
    // convention the decoder used in phase 2, and what discards the write
    // in the register file. The address is checked on every instruction,
    // including trapping ones; the data only matters when the address is
    // nonzero.
    output wire [ 4:0] o_retire_rd_waddr,
    output wire [31:0] o_retire_rd_wdata,
    // The address this instruction was fetched from.
    output wire [31:0] o_retire_pc,
    // The address the next instruction will be fetched from: the pc plus
    // four, or the branch or jump target when a branch is taken or a jump
    // is executed. This is what proves your branch targets, `jal`/`jalr`
    // targets, and `jalr`'s cleared low bit are right.
    output wire [31:0] o_retire_next_pc
);
  // Your implementation goes under here
  // ------------------------------------
  reg  [31:0] pc;
  wire [31:0] next_pc;
  always @(posedge i_clk) begin
    if (i_rst) begin
      pc <= RESET_ADDR;
    end else begin
      pc <= next_pc;
    end
  end
  assign o_imem_raddr = pc;

  // Decoder outputs
  wire        dec_legal;
  wire        dec_halt;
  wire [ 4:0] dec_rs1;
  wire [ 4:0] dec_rs2;
  wire [ 4:0] dec_rd;
  wire [31:0] dec_immediate;
  wire        dec_op1_sel;
  wire        dec_op2_sel;
  wire [ 2:0] dec_alu_opsel;
  wire        dec_alu_sub;
  wire        dec_alu_unsigned;
  wire        dec_alu_arith;
  wire        dec_branch;
  wire        dec_jump;
  wire        dec_branch_equal;
  wire        dec_branch_unsigned;
  wire        dec_branch_invert;
  wire        dec_dmem_ren;
  wire        dec_dmem_wen;
  wire [ 1:0] dec_dmem_align;
  wire        dec_dmem_memb;
  wire        dec_dmem_memh;
  wire        dec_dmem_memw;
  wire        dec_dmem_memu;
  wire [ 3:0] dec_rd_sel;
  wire        dec_pc_sel;

  decoder decoder_inst (
      .i_inst           (i_imem_rdata),
      .o_legal          (dec_legal),
      .o_halt           (dec_halt),
      .o_rs1            (dec_rs1),
      .o_rs2            (dec_rs2),
      .o_rd             (dec_rd),
      .o_immediate      (dec_immediate),
      .o_op1_sel        (dec_op1_sel),
      .o_op2_sel        (dec_op2_sel),
      .o_alu_opsel      (dec_alu_opsel),
      .o_alu_sub        (dec_alu_sub),
      .o_alu_unsigned   (dec_alu_unsigned),
      .o_alu_arith      (dec_alu_arith),
      .o_branch         (dec_branch),
      .o_jump           (dec_jump),
      .o_branch_equal   (dec_branch_equal),
      .o_branch_unsigned(dec_branch_unsigned),
      .o_branch_invert  (dec_branch_invert),
      .o_dmem_ren       (dec_dmem_ren),
      .o_dmem_wen       (dec_dmem_wen),
      .o_dmem_align     (dec_dmem_align),
      .o_dmem_memb      (dec_dmem_memb),
      .o_dmem_memh      (dec_dmem_memh),
      .o_dmem_memw      (dec_dmem_memw),
      .o_dmem_memu      (dec_dmem_memu),
      .o_rd_sel         (dec_rd_sel),
      .o_pc_sel         (dec_pc_sel)
  );

  // Only report (and read) source registers the instruction actually uses.
  // rs1: everything legal except lui, auipc, jal and ebreak.
  // rs2: only R-type, stores and branches.
  wire [6:0] opcode = i_imem_rdata[6:0];
  wire uses_rs1 = dec_legal & ~dec_halt & (opcode != 7'b0110111) &  // lui
  (opcode != 7'b0010111) &  // auipc
  (opcode != 7'b1101111);  // jal
  wire uses_rs2 = dec_legal & ((opcode == 7'b0110011) |  // R-type
  (opcode == 7'b0100011) |  // store
  (opcode == 7'b1100011));  // branch
  wire [4:0] rs1_raddr = uses_rs1 ? dec_rs1 : 5'd0;
  wire [4:0] rs2_raddr = uses_rs2 ? dec_rs2 : 5'd0;

  wire [31:0] rs1_data, rs2_data;
  wire [ 4:0] rd_waddr;
  wire [31:0] rd_wdata;

  rf #(
      .BYPASS_EN(0)
  ) rf_instance (
      .i_clk      (i_clk),
      .i_rst      (i_rst),
      .i_rs1_raddr(rs1_raddr),
      .o_rs1_rdata(rs1_data),
      .i_rs2_raddr(rs2_raddr),
      .o_rs2_rdata(rs2_data),
      // TODO: remove once the write enable from rf is dropped
      .i_rd_wen   (1'b1),
      .i_rd_waddr (rd_waddr),
      .i_rd_wdata (rd_wdata)
  );

  wire [31:0] alu_op1 = dec_op1_sel ? pc : rs1_data;
  wire [31:0] alu_op2 = dec_op2_sel ? dec_immediate : rs2_data;
  wire [31:0] alu_result;
  wire        alu_eq;
  wire        alu_slt;

  alu alu_inst (
      .i_opsel   (dec_alu_opsel),
      .i_sub     (dec_alu_sub),
      .i_unsigned(dec_alu_unsigned),
      .i_arith   (dec_alu_arith),
      .i_op1     (alu_op1),
      .i_op2     (alu_op2),
      .o_result  (alu_result),
      .o_eq      (alu_eq),
      .o_slt     (alu_slt)
  );

  wire branch_cond = dec_branch_equal ? alu_eq : alu_slt;
  wire branch_taken = dec_branch & (branch_cond ^ dec_branch_invert);

  wire [31:0] pc_plus_4 = pc + 32'd4;
  wire [31:0] pc_plus_imm = pc + dec_immediate;
  wire [31:0] jalr_target = {alu_result[31:1], 1'b0};

  wire [1:0] byte_offset = alu_result[1:0];
  wire misaligned = (dec_dmem_ren | dec_dmem_wen) & |(byte_offset & dec_dmem_align);
  wire trap = ~dec_legal | misaligned;

  assign next_pc = trap                      ? pc_plus_4 :
                   dec_pc_sel                ? jalr_target :
                   (branch_taken | dec_jump) ? pc_plus_imm :
                                               pc_plus_4;

  wire mem_ren = dec_dmem_ren & ~trap;
  wire mem_wen = dec_dmem_wen & ~trap;
  wire [3:0] access_mask = dec_dmem_memw ? 4'b1111 :
                           dec_dmem_memh ? (byte_offset[1] ? 4'b1100 : 4'b0011) :
                           dec_dmem_memb ? (4'b0001 << byte_offset) :
                                           4'b0000;

  assign o_dmem_addr  = {alu_result[31:2], 2'b00};
  assign o_dmem_ren   = mem_ren;
  assign o_dmem_wen   = mem_wen;
  assign o_dmem_mask  = (mem_ren | mem_wen) ? access_mask : 4'b0000;
  assign o_dmem_wdata = rs2_data << {byte_offset, 3'b000};

  wire [31:0] load_shifted = i_dmem_rdata >> {byte_offset, 3'b000};
  wire [31:0] load_data =
      dec_dmem_memb ? {{24{~dec_dmem_memu & load_shifted[7]}},  load_shifted[7:0]} :
      dec_dmem_memh ? {{16{~dec_dmem_memu & load_shifted[15]}}, load_shifted[15:0]} :
                      i_dmem_rdata;

  assign rd_wdata = dec_rd_sel[3] ? load_data :
                    dec_rd_sel[2] ? pc_plus_4 :
                    dec_rd_sel[1] ? dec_immediate :
                                    alu_result;
  assign rd_waddr = trap ? 5'd0 : dec_rd;

  // Retire interface.
  assign o_retire_valid = ~i_rst;
  assign o_retire_inst = i_imem_rdata;
  assign o_retire_trap = trap;
  assign o_retire_halt = dec_halt;
  assign o_retire_rs1_raddr = rs1_raddr;
  assign o_retire_rs1_rdata = rs1_data;
  assign o_retire_rs2_raddr = rs2_raddr;
  assign o_retire_rs2_rdata = rs2_data;
  assign o_retire_rd_waddr = rd_waddr;
  assign o_retire_rd_wdata = rd_wdata;
  assign o_retire_pc = pc;
  assign o_retire_next_pc = next_pc;

endmodule

`default_nettype wire
