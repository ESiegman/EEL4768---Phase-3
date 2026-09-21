`timescale 1ns / 1ps
`default_nettype none

// part A is a hand-written program at RESET_ADDR 0x1000 covering what the
// recorded trace leaves don't-care, part B replays the 22661 vectors of
// traces/hart.trace. no expected value is read out of hart.v: they come from
// its port comments, the phase 3 pdf and the trace
module hart_tb;

    // two instances because RESET_ADDR is a parameter: part A needs a
    // nonzero one, part B needs 0 to match the trace. each gets its own
    // memories, and the idle one is held in reset
    reg clk;
    reg rst_a;
    reg rst_b;

    // part A instance: nonzero reset address, its own memories
    wire [31:0] imem_raddr_a;
    wire [31:0] imem_rdata_a;
    wire [31:0] dmem_addr_a;
    wire        dmem_ren_a;
    wire        dmem_wen_a;
    wire [31:0] dmem_wdata_a;
    wire [ 3:0] dmem_mask_a;
    wire [31:0] dmem_rdata_a;
    wire        rt_valid_a;
    wire [31:0] rt_inst_a;
    wire        rt_trap_a;
    wire        rt_halt_a;
    wire [ 4:0] rt_rs1a_a;
    wire [31:0] rt_rs1d_a;
    wire [ 4:0] rt_rs2a_a;
    wire [31:0] rt_rs2d_a;
    wire [ 4:0] rt_rda_a;
    wire [31:0] rt_rdd_a;
    wire [31:0] rt_pc_a;
    wire [31:0] rt_npc_a;

    // part B instance: reset address 0, matching the trace
    wire [31:0] imem_raddr_b;
    wire [31:0] imem_rdata_b;
    wire [31:0] dmem_addr_b;
    wire        dmem_ren_b;
    wire        dmem_wen_b;
    wire [31:0] dmem_wdata_b;
    wire [ 3:0] dmem_mask_b;
    wire [31:0] dmem_rdata_b;
    wire        rt_valid_b;
    wire [31:0] rt_inst_b;
    wire        rt_trap_b;
    wire        rt_halt_b;
    wire [ 4:0] rt_rs1a_b;
    wire [31:0] rt_rs1d_b;
    wire [ 4:0] rt_rs2a_b;
    wire [31:0] rt_rs2d_b;
    wire [ 4:0] rt_rda_b;
    wire [31:0] rt_rdd_b;
    wire [31:0] rt_pc_b;
    wire [31:0] rt_npc_b;

    hart #(.RESET_ADDR(32'h0000_1000)) dut_a (
        .i_clk               (clk),
        .i_rst               (rst_a),
        .o_imem_raddr        (imem_raddr_a),
        .i_imem_rdata        (imem_rdata_a),
        .o_dmem_addr         (dmem_addr_a),
        .o_dmem_ren          (dmem_ren_a),
        .o_dmem_wen          (dmem_wen_a),
        .o_dmem_wdata        (dmem_wdata_a),
        .o_dmem_mask         (dmem_mask_a),
        .i_dmem_rdata        (dmem_rdata_a),
        .o_retire_valid      (rt_valid_a),
        .o_retire_inst       (rt_inst_a),
        .o_retire_trap       (rt_trap_a),
        .o_retire_halt       (rt_halt_a),
        .o_retire_rs1_raddr  (rt_rs1a_a),
        .o_retire_rs1_rdata  (rt_rs1d_a),
        .o_retire_rs2_raddr  (rt_rs2a_a),
        .o_retire_rs2_rdata  (rt_rs2d_a),
        .o_retire_rd_waddr   (rt_rda_a),
        .o_retire_rd_wdata   (rt_rdd_a),
        .o_retire_pc         (rt_pc_a),
        .o_retire_next_pc    (rt_npc_a)
    );

    hart #(.RESET_ADDR(32'h0000_0000)) dut_b (
        .i_clk               (clk),
        .i_rst               (rst_b),
        .o_imem_raddr        (imem_raddr_b),
        .i_imem_rdata        (imem_rdata_b),
        .o_dmem_addr         (dmem_addr_b),
        .o_dmem_ren          (dmem_ren_b),
        .o_dmem_wen          (dmem_wen_b),
        .o_dmem_wdata        (dmem_wdata_b),
        .o_dmem_mask         (dmem_mask_b),
        .i_dmem_rdata        (dmem_rdata_b),
        .o_retire_valid      (rt_valid_b),
        .o_retire_inst       (rt_inst_b),
        .o_retire_trap       (rt_trap_b),
        .o_retire_halt       (rt_halt_b),
        .o_retire_rs1_raddr  (rt_rs1a_b),
        .o_retire_rs1_rdata  (rt_rs1d_b),
        .o_retire_rs2_raddr  (rt_rs2a_b),
        .o_retire_rs2_rdata  (rt_rs2d_b),
        .o_retire_rd_waddr   (rt_rda_b),
        .o_retire_rd_wdata   (rt_rdd_b),
        .o_retire_pc         (rt_pc_b),
        .o_retire_next_pc    (rt_npc_b)
    );

    // 10 ns clock. testbench-driven inputs only ever change on the falling
    // edge, so nothing races the dut's own sampling edge
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // reads are combinational and writes commit on the rising edge, per byte
    // lane, the way hart.v's port comments describe the external memories.
    // part B's program is 24517 words, and the 255 distinct data words it
    // touches, a few near 0 and a block just under 2^32, do not alias in 4096
    reg [31:0] imem_a [0:4095];    // addr[13:2]
    reg [31:0] dmem_a [0:1023];    // addr[11:2]
    reg [31:0] imem_b [0:32767];   // addr[16:2]
    reg [31:0] dmem_b [0:4095];    // addr[13:2]

    assign imem_rdata_a = imem_a[imem_raddr_a[13:2]];
    assign dmem_rdata_a = dmem_a[dmem_addr_a[11:2]];
    assign imem_rdata_b = imem_b[imem_raddr_b[16:2]];
    assign dmem_rdata_b = dmem_b[dmem_addr_b[13:2]];

    // === 1'b1 rather than a plain if, so an undriven write enable does not
    // write memory full of x instead of simply not writing
    always @(posedge clk) begin
        if (dmem_wen_a === 1'b1) begin
            if (dmem_mask_a[0] === 1'b1) dmem_a[dmem_addr_a[11:2]][ 7: 0] <= dmem_wdata_a[ 7: 0];
            if (dmem_mask_a[1] === 1'b1) dmem_a[dmem_addr_a[11:2]][15: 8] <= dmem_wdata_a[15: 8];
            if (dmem_mask_a[2] === 1'b1) dmem_a[dmem_addr_a[11:2]][23:16] <= dmem_wdata_a[23:16];
            if (dmem_mask_a[3] === 1'b1) dmem_a[dmem_addr_a[11:2]][31:24] <= dmem_wdata_a[31:24];
        end
    end

    always @(posedge clk) begin
        if (dmem_wen_b === 1'b1) begin
            if (dmem_mask_b[0] === 1'b1) dmem_b[dmem_addr_b[13:2]][ 7: 0] <= dmem_wdata_b[ 7: 0];
            if (dmem_mask_b[1] === 1'b1) dmem_b[dmem_addr_b[13:2]][15: 8] <= dmem_wdata_b[15: 8];
            if (dmem_mask_b[2] === 1'b1) dmem_b[dmem_addr_b[13:2]][23:16] <= dmem_wdata_b[23:16];
            if (dmem_mask_b[3] === 1'b1) dmem_b[dmem_addr_b[13:2]][31:24] <= dmem_wdata_b[31:24];
        end
    end

    integer passed;
    integer failed;
    integer setup_errors;   // testbench/environment problems, not DUT bugs

    // field ids, for the per-field mismatch tally and for naming a mismatch
    // when one is printed
    localparam integer F_PC        =  0;
    localparam integer F_INST      =  1;
    localparam integer F_TRAP      =  2;
    localparam integer F_HALT      =  3;
    localparam integer F_RS1A      =  4;
    localparam integer F_RS1D      =  5;
    localparam integer F_RS2A      =  6;
    localparam integer F_RS2D      =  7;
    localparam integer F_RDA       =  8;
    localparam integer F_RDD       =  9;
    localparam integer F_REN       = 10;
    localparam integer F_WEN       = 11;
    localparam integer F_MADDR     = 12;
    localparam integer F_MMASK     = 13;
    localparam integer F_MWDATA    = 14;
    localparam integer F_NPC       = 15;
    localparam integer F_VALID     = 16;   // spec rules start here
    localparam integer F_IMEMADDR  = 17;
    localparam integer F_RS1ZA     = 18;
    localparam integer F_RS1ZD     = 19;
    localparam integer F_RS2ZA     = 20;
    localparam integer F_RS2ZD     = 21;
    localparam integer NFIELD      = 22;
    localparam integer FIRST_RULE  = 16;

    integer fmiss [0:21];

    // left-justify a group name so the per-group summary lines up. a reg
    // holding a string is right-justified with NUL padding, so the shift
    // has to be worked out from the length rather than done by %-24s
    function [8*24:1] pad24;
        input [8*64:1] s;
        integer n;
        reg [8*64:1] t;
        reg [8*24:1] base;
        begin
            t = s;
            n = 0;
            while (t != 0) begin
                t = t >> 8;
                n = n + 1;
            end
            base = s;
            if (n >= 24) pad24 = base;
            else         pad24 = (base << (8*(24-n))) | ({24{8'h20}} >> (8*n));
        end
    endfunction

    function [8*24:1] fname;
        input integer k;
        begin
            case (k)
                F_PC:       fname = "pc";
                F_INST:     fname = "inst";
                F_TRAP:     fname = "trap";
                F_HALT:     fname = "halt";
                F_RS1A:     fname = "rs1_raddr";
                F_RS1D:     fname = "rs1_rdata";
                F_RS2A:     fname = "rs2_raddr";
                F_RS2D:     fname = "rs2_rdata";
                F_RDA:      fname = "rd_waddr";
                F_RDD:      fname = "rd_wdata";
                F_REN:      fname = "dmem_ren";
                F_WEN:      fname = "dmem_wen";
                F_MADDR:    fname = "mem_addr";
                F_MMASK:    fname = "mem_mask";
                F_MWDATA:   fname = "mem_wdata";
                F_NPC:      fname = "next_pc";
                F_VALID:    fname = "retire_valid";
                F_IMEMADDR: fname = "imem_raddr";
                F_RS1ZA:    fname = "unread rs1_raddr";
                F_RS1ZD:    fname = "unread rs1_rdata";
                F_RS2ZA:    fname = "unread rs2_raddr";
                F_RS2ZD:    fname = "unread rs2_rdata";
                default:    fname = "?";
            endcase
        end
    endfunction

    // a zero-delay combinational loop makes vvp spin forever inside one
    // timestep, and run_test.sh has no timeout. counting value changes that
    // happen without $time advancing turns that hang into a verdict. the
    // classic cause is rf with BYPASS_EN = 1, where addi x5, x5, 1 feeds its
    // own write data back into its source operand
    localparam integer WD_LIMIT = 10000;

    integer   wd_cnt_a;
    integer   wd_cnt_b;
    reg [63:0] wd_t_a;
    reg [63:0] wd_t_b;
    reg        wd_tripped;

    always @(rt_rdd_a or rt_rs1d_a or rt_rs2d_a or rt_npc_a) begin
        if ($time === wd_t_a) begin
            wd_cnt_a = wd_cnt_a + 1;
            if (wd_cnt_a > WD_LIMIT) watchdog_trip(0, wd_cnt_a);
        end else begin
            wd_t_a   = $time;
            wd_cnt_a = 0;
        end
    end

    always @(rt_rdd_b or rt_rs1d_b or rt_rs2d_b or rt_npc_b) begin
        if ($time === wd_t_b) begin
            wd_cnt_b = wd_cnt_b + 1;
            if (wd_cnt_b > WD_LIMIT) watchdog_trip(1, wd_cnt_b);
        end else begin
            wd_t_b   = $time;
            wd_cnt_b = 0;
        end
    end

    task watchdog_trip;
        input integer which;
        input integer count;
        begin
            if (!wd_tripped) begin
                wd_tripped = 1'b1;
                failed = failed + 1;
                $display("");
                $display("[FAIL] watchdog: the design is stuck in a combinational loop");
                $display("         %0s settled %0d times at t=%0t without simulation time advancing",
                         (which == 0) ? "the part A hart" : "the part B hart", count, $time);
                $display("         most likely cause: rf instantiated with BYPASS_EN = 1. In a");
                $display("         single-cycle hart the write-back value is computed from the");
                $display("         operands it is then forwarded onto, so `addi x5, x5, 1` feeds");
                $display("         itself. Instantiate rf with BYPASS_EN = 0.");
                $display("         Any other wire that combinationally depends on itself does");
                $display("         the same thing -- check the next_pc and rd_wdata cones.");
                report_verdict;
                // breaking the loop is what lets $finish take effect at
                // all, because while it is live the scheduler never leaves
                // this timestep. an all-zero word is an illegal encoding, so
                // no register is written and the forwarding path goes idle
                force imem_rdata_a = 32'h00000000;
                force imem_rdata_b = 32'h00000000;
                $finish;
            end
        end
    endtask

    // every compare is !== rather than !=, so an x or z from the dut fails
    // here instead of quietly comparing unknown and returning unknown. an x
    // on the expected side means don't-care and is skipped, which is how the
    // trace's don't-care columns are honoured
    localparam integer MODE_COUNT = 0;   // tally mismatches, print nothing
    localparam integer MODE_PRINT = 1;   // print mismatches, tally nothing
    localparam integer MODE_QUIET = 2;   // neither; just set `step_bad`

    integer chk_mode;
    reg     step_bad;

    task chk;
        input integer      fid;
        input [31:0]       got;
        input [31:0]       want;
        begin
            if ((^want) === 1'bx) begin
                // don't-care column: whatever the design drives is accepted
            end else if (got !== want) begin
                step_bad = 1'b1;
                if (chk_mode == MODE_COUNT)
                    fmiss[fid] = fmiss[fid] + 1;
                else if (chk_mode == MODE_PRINT)
                    $display("         %0s: got %h, expected %h", fname(fid), got, want);
            end
        end
    endtask

    // store data only means anything in the lanes the mask selects. the rest
    // may hold garbage or a replicated byte, so they are never compared
    integer chk_lane;
    reg     chk_wd_bad;

    task chk_store_data;
        input [31:0] got;
        input [31:0] want;
        input [31:0] mask;
        reg   [ 7:0] want_lane;
        reg   [ 7:0] got_lane;
        begin
            chk_wd_bad = 1'b0;
            if ((^mask) !== 1'bx) begin
                for (chk_lane = 0; chk_lane < 4; chk_lane = chk_lane + 1) begin
                    if (mask[chk_lane] === 1'b1) begin
                        want_lane = want[8*chk_lane +: 8];
                        got_lane  = got [8*chk_lane +: 8];
                        if ((^want_lane) !== 1'bx && got_lane !== want_lane) begin
                            step_bad   = 1'b1;
                            chk_wd_bad = 1'b1;
                            if (chk_mode == MODE_PRINT)
                                $display("         mem_wdata lane %0d: got %h, expected %h",
                                         chk_lane, got_lane, want_lane);
                        end
                    end
                end
                if (chk_wd_bad && chk_mode == MODE_COUNT)
                    fmiss[F_MWDATA] = fmiss[F_MWDATA] + 1;
            end
        end
    endtask

    // the sampled dut outputs and the expected values for one retire, in one
    // set of registers so a single compare routine serves both parts
    reg [31:0] g_imem_raddr;
    reg        g_valid;
    reg [31:0] g_inst;
    reg        g_trap;
    reg        g_halt;
    reg [ 4:0] g_rs1a;
    reg [31:0] g_rs1d;
    reg [ 4:0] g_rs2a;
    reg [31:0] g_rs2d;
    reg [ 4:0] g_rda;
    reg [31:0] g_rdd;
    reg [31:0] g_pc;
    reg [31:0] g_npc;
    reg [31:0] g_maddr;
    reg        g_ren;
    reg        g_wen;
    reg [31:0] g_wdata;
    reg [ 3:0] g_mask;

    reg [31:0] e_pc;
    reg [31:0] e_inst;
    reg [31:0] e_trap;
    reg [31:0] e_halt;
    reg [31:0] e_rs1a;
    reg [31:0] e_rs1d;
    reg [31:0] e_rs2a;
    reg [31:0] e_rs2d;
    reg [31:0] e_rda;
    reg [31:0] e_rdd;
    reg [31:0] e_memop;   // 0 none, 1 load, 2 store
    reg [31:0] e_maddr;
    reg [31:0] e_mmask;
    reg [31:0] e_mwdata;
    reg [31:0] e_npc;
    reg        e_rs1_dc;  // trace does not check rs1; the spec rule applies
    reg        e_rs2_dc;

    // sample the retire interface of one instance. called immediately after
    // @(posedge clk) with blocking assignments, so it sees what the retiring
    // instruction produced: the dut's registers update through nonblocking
    // assignments and are not visible yet. even #1 here would read the next
    // instruction instead
    task sample_a;
        begin
            g_imem_raddr = imem_raddr_a;
            g_valid = rt_valid_a; g_inst = rt_inst_a;
            g_trap  = rt_trap_a;  g_halt = rt_halt_a;
            g_rs1a  = rt_rs1a_a;  g_rs1d = rt_rs1d_a;
            g_rs2a  = rt_rs2a_a;  g_rs2d = rt_rs2d_a;
            g_rda   = rt_rda_a;   g_rdd  = rt_rdd_a;
            g_pc    = rt_pc_a;    g_npc  = rt_npc_a;
            g_maddr = dmem_addr_a;
            g_ren   = dmem_ren_a; g_wen  = dmem_wen_a;
            g_wdata = dmem_wdata_a;
            g_mask  = dmem_mask_a;
        end
    endtask

    task sample_b;
        begin
            g_imem_raddr = imem_raddr_b;
            g_valid = rt_valid_b; g_inst = rt_inst_b;
            g_trap  = rt_trap_b;  g_halt = rt_halt_b;
            g_rs1a  = rt_rs1a_b;  g_rs1d = rt_rs1d_b;
            g_rs2a  = rt_rs2a_b;  g_rs2d = rt_rs2d_b;
            g_rda   = rt_rda_b;   g_rdd  = rt_rdd_b;
            g_pc    = rt_pc_b;    g_npc  = rt_npc_b;
            g_maddr = dmem_addr_b;
            g_ren   = dmem_ren_b; g_wen  = dmem_wen_b;
            g_wdata = dmem_wdata_b;
            g_mask  = dmem_mask_b;
        end
    endtask

    // one retired instruction, field by field. run twice per vector: once to
    // decide pass or fail and tally the fields, then again to print the
    // mismatches of a vector already known to have failed
    task run_checks;
        input integer mode;
        begin
            chk_mode = mode;

            // spec rules that hold on every cycle after reset deasserts
            chk(F_VALID,    {31'b0, g_valid}, 32'd1);
            chk(F_IMEMADDR, g_imem_raddr,     e_pc);

            chk(F_PC,   g_pc,             e_pc);
            chk(F_INST, g_inst,           e_inst);
            chk(F_TRAP, {31'b0, g_trap},  e_trap);
            chk(F_HALT, {31'b0, g_halt},  e_halt);

            // the trace leaves rs1/rs2 don't-care for classes that do not
            // read them, but hart.v requires 5'd0 there, so that rule gets
            // checked in place of nothing
            if (e_rs1_dc) begin
                chk(F_RS1ZA, {27'b0, g_rs1a}, 32'd0);
                chk(F_RS1ZD, g_rs1d,          32'd0);
            end else begin
                chk(F_RS1A, {27'b0, g_rs1a}, e_rs1a);
                chk(F_RS1D, g_rs1d,          e_rs1d);
            end

            if (e_rs2_dc) begin
                chk(F_RS2ZA, {27'b0, g_rs2a}, 32'd0);
                chk(F_RS2ZD, g_rs2d,          32'd0);
            end else begin
                chk(F_RS2A, {27'b0, g_rs2a}, e_rs2a);
                chk(F_RS2D, g_rs2d,          e_rs2d);
            end

            // rd_waddr is checked on every instruction, trapping ones
            // included. rd_wdata only matters when the address is nonzero,
            // which is exactly when e_rdd is not a don't-care
            chk(F_RDA, {27'b0, g_rda}, e_rda);
            chk(F_RDD, g_rdd,          e_rdd);

            chk(F_REN, {31'b0, g_ren}, (e_memop === 32'd1) ? 32'd1 : 32'd0);
            chk(F_WEN, {31'b0, g_wen}, (e_memop === 32'd2) ? 32'd1 : 32'd0);

            chk(F_MADDR, g_maddr,          e_maddr);
            chk(F_MMASK, {28'b0, g_mask},  e_mmask);
            chk_store_data(g_wdata, e_mwdata, e_mmask);

            chk(F_NPC, g_npc, e_npc);
        end
    endtask

    // the part A program is assembled here rather than written out as hex,
    // so it reads like assembly. field layouts are the ones on the RV32I
    // reference card, and check_encoders below pins every word the program
    // uses to a hex value worked out by hand, so a wrong encoder shows up as
    // a setup error instead of silently testing a different program
    localparam [6:0] OPC_LUI    = 7'b0110111;
    localparam [6:0] OPC_AUIPC  = 7'b0010111;
    localparam [6:0] OPC_JAL    = 7'b1101111;
    localparam [6:0] OPC_JALR   = 7'b1100111;
    localparam [6:0] OPC_LOAD   = 7'b0000011;
    localparam [6:0] OPC_STORE  = 7'b0100011;
    localparam [6:0] OPC_OPIMM  = 7'b0010011;
    localparam [6:0] OPC_OP     = 7'b0110011;
    localparam [6:0] OPC_FENCE  = 7'b0001111;
    localparam [6:0] OPC_SYSTEM = 7'b1110011;

    function [31:0] enc_r;
        input [ 6:0] f7;
        input [ 4:0] rs2;
        input [ 4:0] rs1;
        input [ 2:0] f3;
        input [ 4:0] rd;
        input [ 6:0] opc;
        begin
            // 7 + 5 + 5 + 3 + 5 + 7 = 32
            enc_r = {f7, rs2, rs1, f3, rd, opc};
        end
    endfunction

    function [31:0] enc_i;
        input [11:0] imm;
        input [ 4:0] rs1;
        input [ 2:0] f3;
        input [ 4:0] rd;
        input [ 6:0] opc;
        begin
            // 12 + 5 + 3 + 5 + 7 = 32
            enc_i = {imm, rs1, f3, rd, opc};
        end
    endfunction

    function [31:0] enc_s;
        input [11:0] imm;
        input [ 4:0] rs2;
        input [ 4:0] rs1;
        input [ 2:0] f3;
        input [ 6:0] opc;
        begin
            // the immediate is split so rs1 and rs2 stay where R-type has
            // them. 7 + 5 + 5 + 3 + 5 + 7 = 32
            enc_s = {imm[11:5], rs2, rs1, f3, imm[4:0], opc};
        end
    endfunction

    function [31:0] enc_u;
        input [19:0] imm;
        input [ 4:0] rd;
        input [ 6:0] opc;
        begin
            // the one format that is not sign-extended. 20 + 5 + 7 = 32
            enc_u = {imm, rd, opc};
        end
    endfunction

    // off is the byte offset. bit 0 is not encoded, the same way the J-format
    // immediate drops it
    function [31:0] enc_j;
        input [20:0] off;
        input [ 4:0] rd;
        input [ 6:0] opc;
        begin
            // 1 + 10 + 1 + 8 + 5 + 7 = 32
            enc_j = {off[20], off[10:1], off[11], off[19:12], rd, opc};
        end
    endfunction

    function [31:0] i_lui;    input [19:0] imm; input [4:0] rd;
        begin i_lui   = enc_u(imm, rd, OPC_LUI);   end endfunction
    function [31:0] i_auipc;  input [19:0] imm; input [4:0] rd;
        begin i_auipc = enc_u(imm, rd, OPC_AUIPC); end endfunction
    function [31:0] i_jal;    input [20:0] off; input [4:0] rd;
        begin i_jal   = enc_j(off, rd, OPC_JAL);   end endfunction
    function [31:0] i_jalr;   input [11:0] imm; input [4:0] rs1; input [4:0] rd;
        begin i_jalr  = enc_i(imm, rs1, 3'b000, rd, OPC_JALR); end endfunction
    function [31:0] i_addi;   input [11:0] imm; input [4:0] rs1; input [4:0] rd;
        begin i_addi  = enc_i(imm, rs1, 3'b000, rd, OPC_OPIMM); end endfunction
    function [31:0] i_add;    input [4:0] rs2; input [4:0] rs1; input [4:0] rd;
        begin i_add   = enc_r(7'b0000000, rs2, rs1, 3'b000, rd, OPC_OP); end endfunction
    function [31:0] i_mul;    input [4:0] rs2; input [4:0] rs1; input [4:0] rd;
        begin i_mul   = enc_r(7'b0000001, rs2, rs1, 3'b000, rd, OPC_OP); end endfunction
    function [31:0] i_lb;     input [11:0] imm; input [4:0] rs1; input [4:0] rd;
        begin i_lb    = enc_i(imm, rs1, 3'b000, rd, OPC_LOAD); end endfunction
    function [31:0] i_lh;     input [11:0] imm; input [4:0] rs1; input [4:0] rd;
        begin i_lh    = enc_i(imm, rs1, 3'b001, rd, OPC_LOAD); end endfunction
    function [31:0] i_lw;     input [11:0] imm; input [4:0] rs1; input [4:0] rd;
        begin i_lw    = enc_i(imm, rs1, 3'b010, rd, OPC_LOAD); end endfunction
    function [31:0] i_sh;     input [11:0] imm; input [4:0] rs2; input [4:0] rs1;
        begin i_sh    = enc_s(imm, rs2, rs1, 3'b001, OPC_STORE); end endfunction
    function [31:0] i_sw;     input [11:0] imm; input [4:0] rs2; input [4:0] rs1;
        begin i_sw    = enc_s(imm, rs2, rs1, 3'b010, OPC_STORE); end endfunction

    localparam [31:0] I_EBREAK = 32'h00100073;
    localparam [31:0] I_ECALL  = 32'h00000073;
    localparam [31:0] I_ILLEGAL = 32'hffffffff;

    task expect_word;
        input [511:0] label;
        input [ 31:0] got;
        input [ 31:0] want;
        begin
            if (got !== want) begin
                setup_errors = setup_errors + 1;
                $display("[SETUP] encoder wrong for %0s: built %h, expected %h", label, got, want);
            end
        end
    endtask

    // every word the part A program uses, pinned to the hex it must be
    task check_encoders;
        begin
            expect_word("lui x5, 0xABCDE",   i_lui(20'hABCDE, 5'd5),        32'habcde2b7);
            expect_word("auipc x6, 0xFFFFF", i_auipc(20'hFFFFF, 5'd6),      32'hfffff317);
            expect_word("addi x7, x5, 2047", i_addi(12'h7ff, 5'd5, 5'd7),   32'h7ff28393);
            expect_word("jal x1, +12",       i_jal(21'd12, 5'd1),           32'h00c000ef);
            expect_word("jal x0, +12",       i_jal(21'd12, 5'd0),           32'h00c0006f);
            expect_word("jal x2, -4",        i_jal(-21'sd4, 5'd2),          32'hffdff16f);
            expect_word("auipc x3, 0",       i_auipc(20'h00000, 5'd3),      32'h00000197);
            expect_word("jalr x3, 13(x3)",   i_jalr(12'd13, 5'd3, 5'd3),    32'h00d181e7);
            expect_word("addi x10, x0, 512", i_addi(12'h200, 5'd0, 5'd10),  32'h20000513);
            expect_word("sw x5, 0(x10)",     i_sw(12'd0, 5'd5, 5'd10),      32'h00552023);
            expect_word("sw x6, 1(x10)",     i_sw(12'd1, 5'd6, 5'd10),      32'h006520a3);
            expect_word("sh x6, 3(x10)",     i_sh(12'd3, 5'd6, 5'd10),      32'h006511a3);
            expect_word("lw x11, 2(x10)",    i_lw(12'd2, 5'd10, 5'd11),     32'h00252583);
            expect_word("lh x12, 1(x10)",    i_lh(12'd1, 5'd10, 5'd12),     32'h00151603);
            expect_word("lw x13, 0(x10)",    i_lw(12'd0, 5'd10, 5'd13),     32'h00052683);
            expect_word("add x14, x11, x12", i_add(5'd12, 5'd11, 5'd14),    32'h00c58733);
            expect_word("lb x15, 3(x10)",    i_lb(12'd3, 5'd10, 5'd15),     32'h00350783);
            expect_word("mul x7, x5, x6",    i_mul(5'd6, 5'd5, 5'd7),       32'h026283b3);
            expect_word("addi x17, x7, 0",   i_addi(12'd0, 5'd7, 5'd17),    32'h00038893);
            expect_word("add x18, x7, x17",  i_add(5'd17, 5'd7, 5'd18),     32'h01138933);
        end
    endtask

    // begin_step sets what every instruction does unless it says otherwise:
    // no trap, no halt, no register write, no memory access, no source
    // register reported, next_pc = pc + 4. the want_* tasks override only
    // what this one really does, and end_step waits an edge and checks it
    reg [511:0] e_label;

    task begin_step;
        input [511:0] label;
        input [ 31:0] pc;
        begin
            e_label  = label;
            e_pc     = pc;
            e_npc    = pc + 32'd4;
            e_trap   = 32'd0;
            e_halt   = 32'd0;
            e_rs1a   = 32'd0;
            e_rs1d   = 32'd0;
            e_rs2a   = 32'd0;
            e_rs2d   = 32'd0;
            e_rda    = 32'd0;
            e_rdd    = 32'hxxxxxxxx;
            e_memop  = 32'd0;
            e_maddr  = 32'hxxxxxxxx;
            e_mmask  = 32'hxxxxxxxx;
            e_mwdata = 32'hxxxxxxxx;
            e_rs1_dc = 1'b0;
            e_rs2_dc = 1'b0;
        end
    endtask

    task want_rs1;
        input [4:0] a;
        input [31:0] d;
        begin e_rs1a = {27'b0, a}; e_rs1d = d; end
    endtask

    task want_rs2;
        input [4:0] a;
        input [31:0] d;
        begin e_rs2a = {27'b0, a}; e_rs2d = d; end
    endtask

    task want_rd;
        input [4:0] a;
        input [31:0] d;
        begin e_rda = {27'b0, a}; e_rdd = d; end
    endtask

    task want_load;
        input [31:0] addr;
        input [ 3:0] mask;
        begin e_memop = 32'd1; e_maddr = addr; e_mmask = {28'b0, mask}; end
    endtask

    task want_store;
        input [31:0] addr;
        input [ 3:0] mask;
        input [31:0] wdata;
        begin
            e_memop  = 32'd2;
            e_maddr  = addr;
            e_mmask  = {28'b0, mask};
            e_mwdata = wdata;
        end
    endtask

    task want_trap;    begin e_trap = 32'd1; end endtask
    task want_halt;    begin e_halt = 32'd1; end endtask

    task want_next_pc;
        input [31:0] npc;
        begin e_npc = npc; end
    endtask

    task end_step;
        begin
            @(posedge clk);
            sample_a;
            // the instruction the design must report is whatever sits at
            // this pc in the memory model right now, read from the model and
            // never from the dut
            e_inst = imem_a[e_pc[13:2]];

            step_bad = 1'b0;
            run_checks(MODE_QUIET);

            if (!step_bad) begin
                passed = passed + 1;
                $display("[PASS] %0s", e_label);
            end else begin
                failed = failed + 1;
                $display("[FAIL] %0s", e_label);
                $display("         pc=%h inst=%h t=%0t", e_pc, e_inst, $time);
                run_checks(MODE_PRINT);
            end
        end
    endtask

    reg [8*256:1] prog_path;
    reg [8*256:1] trace_path;
    reg [8*256:1] plus_path;
    reg [8*256:1] line;
    reg [8*64:1]  grp;

    integer prog_fd;
    integer trace_fd;
    integer prog_words;

    task report_verdict;
        begin
            $display("=====================================");
            $display("%0d passed, %0d failed", passed, failed + setup_errors);
            if ((failed + setup_errors) == 0)
                $display("ALL TESTS PASSED");
            else
                $display("TEST FAILED");
        end
    endtask

    task die_no_file;
        input [511:0] what;
        input [8*256:1] p1;
        input [8*256:1] p2;
        input [8*256:1] p3;
        begin
            setup_errors = setup_errors + 1;
            $display("[SETUP] could not open the %0s file. Paths tried, in order:", what);
            $display("           %0s", p1);
            $display("           %0s", p2);
            $display("           %0s", p3);
            $display("         run_test.sh runs vvp from build/, so ../traces/ is the");
            $display("         usual one. Override with +trace=<path> / +program=<path>.");
            report_verdict;
            $finish;
        end
    endtask

    localparam integer MAX_GROUPS   = 64;
    localparam integer MAX_REPORTED = 20;

    reg [8*64:1] gname [0:63];
    integer      gtotal  [0:63];
    integer      gpassed [0:63];
    integer      ngroups;
    integer      cur_group;

    integer vec;
    integer vec_passed;
    integer vec_failed;
    integer reported;
    integer nf;
    integer ng;
    integer code;
    integer trace_done;
    integer nlisted;
    integer i;

    initial begin
        passed       = 0;
        failed       = 0;
        setup_errors = 0;
        wd_cnt_a     = 0;
        wd_cnt_b     = 0;
        wd_t_a       = 64'd0;
        wd_t_b       = 64'd0;
        wd_tripped   = 1'b0;
        chk_mode     = MODE_QUIET;
        step_bad     = 1'b0;
        ngroups      = 0;
        cur_group    = -1;
        vec          = 0;
        vec_passed   = 0;
        vec_failed   = 0;
        reported     = 0;
        trace_done   = 0;

        for (i = 0; i < NFIELD; i = i + 1) fmiss[i] = 0;
        for (i = 0; i < MAX_GROUPS; i = i + 1) begin
            gtotal[i]  = 0;
            gpassed[i] = 0;
            gname[i]   = "?";
        end

        // both harts stay in reset until their own section starts
        rst_a = 1'b1;
        rst_b = 1'b1;

        // +vcd is opt-in: 22661 cycles of every signal in two harts is a
        // very large file
        if ($test$plusargs("vcd")) begin
            $dumpfile("hart.vcd");
            $dumpvars(0, hart_tb);
        end

        $display("========== hart testbench ==========");

        // +program=<path> and +trace=<path> win, then traces/ for a run from
        // the repo root, then ../traces/ for the build/ directory run_test.sh
        // runs vvp in
        prog_fd = 0;
        if ($value$plusargs("program=%s", plus_path)) begin
            prog_fd = $fopen(plus_path, "r");
            if (prog_fd != 0) prog_path = plus_path;
        end
        if (prog_fd == 0) begin
            prog_fd = $fopen("traces/hart_program.hex", "r");
            if (prog_fd != 0) prog_path = "traces/hart_program.hex";
        end
        if (prog_fd == 0) begin
            prog_fd = $fopen("../traces/hart_program.hex", "r");
            if (prog_fd != 0) prog_path = "../traces/hart_program.hex";
        end
        if (prog_fd == 0)
            die_no_file("program", "+program=<path>", "traces/hart_program.hex",
                        "../traces/hart_program.hex");

        trace_fd = 0;
        if ($value$plusargs("trace=%s", plus_path)) begin
            trace_fd = $fopen(plus_path, "r");
            if (trace_fd != 0) trace_path = plus_path;
        end
        if (trace_fd == 0) begin
            trace_fd = $fopen("traces/hart.trace", "r");
            if (trace_fd != 0) trace_path = "traces/hart.trace";
        end
        if (trace_fd == 0) begin
            trace_fd = $fopen("../traces/hart.trace", "r");
            if (trace_fd != 0) trace_path = "../traces/hart.trace";
        end
        if (trace_fd == 0)
            die_no_file("trace", "+trace=<path>", "traces/hart.trace",
                        "../traces/hart.trace");

        // $readmemh warns unless the range is exactly the number of words in
        // the file, so count them first rather than hardcoding a length a
        // regenerated trace would invalidate
        prog_words = 0;
        code = 1;
        while (code != 0) begin
            code = $fgets(line, prog_fd);
            if (code != 0) begin
                nf = $sscanf(line, "%h", e_inst);
                if (nf == 1) prog_words = prog_words + 1;
            end
        end
        $fclose(prog_fd);

        // zero-fill first. an all-zero word is an illegal encoding, so a
        // fetch outside the program traps instead of reading x
        for (i = 0; i < 32768; i = i + 1) imem_b[i] = 32'h00000000;
        for (i = 0; i < 4096;  i = i + 1) dmem_b[i] = 32'h00000000;
        for (i = 0; i < 4096;  i = i + 1) imem_a[i] = 32'h00000000;
        for (i = 0; i < 1024;  i = i + 1) dmem_a[i] = 32'h00000000;

        if (prog_words > 0 && prog_words <= 32768)
            $readmemh(prog_path, imem_b, 0, prog_words - 1);
        else begin
            setup_errors = setup_errors + 1;
            $display("[SETUP] %0s holds %0d words; expected 1..32768",
                     prog_path, prog_words);
        end

        $display("program: %0s (%0d words)", prog_path, prog_words);
        $display("trace:   %0s", trace_path);

        check_encoders;

        // part A, directed steps. every retire field below was worked out on
        // paper, and they cover the rules the trace writes as don't-care or
        // never exercises at all
        $display("");
        $display("--- directed ---");

        // the program. addresses are absolute, and 0x1000 is RESET_ADDR
        imem_a[32'h1000 >> 2] = i_lui(20'hABCDE, 5'd5);         // rs1/rs2 fields hold 27/28
        imem_a[32'h1004 >> 2] = i_auipc(20'hFFFFF, 5'd6);       // wraps past 2^32
        imem_a[32'h1008 >> 2] = i_addi(12'h7ff, 5'd5, 5'd7);    // rs2 field holds 31
        imem_a[32'h100c >> 2] = i_jal(21'd12, 5'd1);            // link 0x1010, target 0x1018
        imem_a[32'h1010 >> 2] = I_ILLEGAL;                      // only runs if a jump is wrong
        imem_a[32'h1014 >> 2] = i_jal(21'd12, 5'd0);            // writes nothing
        imem_a[32'h1018 >> 2] = i_jal(-21'sd4, 5'd2);           // backward
        imem_a[32'h101c >> 2] = I_ILLEGAL;
        imem_a[32'h1020 >> 2] = i_auipc(20'h00000, 5'd3);       // x3 = 0x1020
        imem_a[32'h1024 >> 2] = i_jalr(12'd13, 5'd3, 5'd3);     // rd == rs1, bit 0 cleared
        imem_a[32'h1028 >> 2] = I_ILLEGAL;
        imem_a[32'h102c >> 2] = i_addi(12'h200, 5'd0, 5'd10);   // data base
        imem_a[32'h1030 >> 2] = i_sw(12'd0, 5'd5, 5'd10);
        imem_a[32'h1034 >> 2] = i_sw(12'd1, 5'd6, 5'd10);       // misaligned word store
        imem_a[32'h1038 >> 2] = i_sh(12'd3, 5'd6, 5'd10);       // misaligned half store
        imem_a[32'h103c >> 2] = i_lw(12'd2, 5'd10, 5'd11);      // misaligned word load
        imem_a[32'h1040 >> 2] = i_lh(12'd1, 5'd10, 5'd12);      // misaligned half load
        imem_a[32'h1044 >> 2] = i_lw(12'd0, 5'd10, 5'd13);      // the trapped stores wrote nothing
        imem_a[32'h1048 >> 2] = i_add(5'd12, 5'd11, 5'd14);     // the trapped loads wrote nothing
        imem_a[32'h104c >> 2] = i_lb(12'd3, 5'd10, 5'd15);      // byte at offset 3: never misaligned
        imem_a[32'h1050 >> 2] = I_ILLEGAL;
        imem_a[32'h1054 >> 2] = I_ECALL;                        // illegal in this course
        imem_a[32'h1058 >> 2] = i_mul(5'd6, 5'd5, 5'd7);        // M extension: illegal
        imem_a[32'h105c >> 2] = 32'h0ff0000f;                   // fence: illegal in this course
        imem_a[32'h1060 >> 2] = i_addi(12'd0, 5'd7, 5'd17);     // mul wrote nothing
        imem_a[32'h1064 >> 2] = I_EBREAK;

        // reset is synchronous, so it needs clock edges to take effect, and
        // it is deasserted on a falling edge so it cannot race the pc
        repeat (2) @(posedge clk);
        @(negedge clk);
        rst_a = 1'b0;

        // 1
        begin_step("lui: rs1/rs2 fields set, both must report x0", 32'h1000);
        want_rd(5'd5, 32'habcde000);
        end_step;

        // 2
        begin_step("auipc: pc-relative, wraps past 2^32", 32'h1004);
        want_rd(5'd6, 32'h00000004);
        end_step;

        // 3
        begin_step("addi: rs2 field set, rs2 must report x0", 32'h1008);
        want_rs1(5'd5, 32'habcde000);
        want_rd(5'd7, 32'habcde7ff);
        end_step;

        // 4
        begin_step("jal x1 forward: link is pc+4, not the target", 32'h100c);
        want_rd(5'd1, 32'h00001010);
        want_next_pc(32'h00001018);
        end_step;

        // 5
        begin_step("jal x2 backward: negative J immediate", 32'h1018);
        want_rd(5'd2, 32'h0000101c);
        want_next_pc(32'h00001014);
        end_step;

        // 6
        begin_step("jal x0: jumps but writes no register", 32'h1014);
        want_next_pc(32'h00001020);
        end_step;

        // 7
        begin_step("auipc x3, 0: x3 = its own pc", 32'h1020);
        want_rd(5'd3, 32'h00001020);
        end_step;

        // 8
        begin_step("jalr rd==rs1: target 0x102d, bit 0 cleared", 32'h1024);
        want_rs1(5'd3, 32'h00001020);
        want_rd(5'd3, 32'h00001028);
        want_next_pc(32'h0000102c);
        end_step;

        // 9
        begin_step("addi x10, x0, 0x200: data base", 32'h102c);
        want_rd(5'd10, 32'h00000200);
        end_step;

        // 10
        begin_step("sw aligned: all four lanes", 32'h1030);
        want_rs1(5'd10, 32'h00000200);
        want_rs2(5'd5,  32'habcde000);
        want_store(32'h00000200, 4'hf, 32'habcde000);
        end_step;

        // 11
        begin_step("sw at +1 traps, and still reports rs1 and rs2", 32'h1034);
        want_rs1(5'd10, 32'h00000200);
        want_rs2(5'd6,  32'h00000004);
        want_trap;
        end_step;

        // 12
        begin_step("sh at odd address traps, no write enable", 32'h1038);
        want_rs1(5'd10, 32'h00000200);
        want_rs2(5'd6,  32'h00000004);
        want_trap;
        end_step;

        // 13
        begin_step("lw at +2 traps, no read enable, rd_waddr 0", 32'h103c);
        want_rs1(5'd10, 32'h00000200);
        want_trap;
        end_step;

        // 14
        begin_step("lh at odd address traps, rs2 must report x0", 32'h1040);
        want_rs1(5'd10, 32'h00000200);
        want_trap;
        end_step;

        // 15
        begin_step("lw back: proves the trapped stores wrote nothing", 32'h1044);
        want_rs1(5'd10, 32'h00000200);
        want_rd(5'd13, 32'habcde000);
        want_load(32'h00000200, 4'hf);
        end_step;

        // 16
        begin_step("add x11+x12: trapped loads wrote nothing, regs reset", 32'h1048);
        want_rs1(5'd11, 32'h00000000);
        want_rs2(5'd12, 32'h00000000);
        want_rd(5'd14, 32'h00000000);
        end_step;

        // 17
        begin_step("lb at +3: byte access never traps, sign-extends", 32'h104c);
        want_rs1(5'd10, 32'h00000200);
        want_rd(5'd15, 32'hffffffab);
        want_load(32'h00000200, 4'h8);
        end_step;

        // 18
        begin_step("all-ones word is an illegal encoding", 32'h1050);
        want_trap;
        end_step;

        // 19
        begin_step("ecall is illegal in this course", 32'h1054);
        want_trap;
        end_step;

        // 20
        begin_step("mul is the M extension, not RV32I", 32'h1058);
        want_trap;
        end_step;

        // 21
        begin_step("fence is illegal in this course", 32'h105c);
        want_trap;
        end_step;

        // 22
        begin_step("addi x17, x7, 0: proves mul wrote nothing", 32'h1060);
        want_rs1(5'd7, 32'habcde7ff);
        want_rd(5'd17, 32'habcde7ff);
        end_step;

        // 23
        begin_step("ebreak halts without trapping, next_pc still pc+4", 32'h1064);
        want_halt;
        end_step;

        // mid-run reset. it must send the pc back to RESET_ADDR and clear
        // all 32 registers, so the two the program filled in read back zero.
        // the program is swapped while reset is held
        @(negedge clk);
        rst_a = 1'b1;
        imem_a[32'h1000 >> 2] = i_add(5'd17, 5'd7, 5'd18);
        imem_a[32'h1004 >> 2] = I_EBREAK;
        repeat (2) @(posedge clk);
        @(negedge clk);
        rst_a = 1'b0;

        // 24
        begin_step("after reset: pc is RESET_ADDR and x7/x17 are cleared", 32'h1000);
        want_rs1(5'd7,  32'h00000000);
        want_rs2(5'd17, 32'h00000000);
        want_rd(5'd18,  32'h00000000);
        end_step;

        // 25
        begin_step("ebreak again after the reset", 32'h1004);
        want_halt;
        end_step;

        @(negedge clk);
        rst_a = 1'b1;

        // part B, one vector per rising edge. don't-cares follow
        // traces/README.md, and where the trace has one, part A's rule runs
        $display("");
        $display("--- trace ---");

        @(negedge clk);
        rst_b = 1'b0;

        while (trace_done == 0) begin
            code = $fgets(line, trace_fd);
            if (code == 0) begin
                trace_done = 1;
            end else begin
                nf = $sscanf(line, "%h %h %h %h %h %h %h %h %h %h %h %h %h %h %h",
                             e_pc, e_inst, e_trap, e_halt,
                             e_rs1a, e_rs1d, e_rs2a, e_rs2d,
                             e_rda, e_rdd,
                             e_memop, e_maddr, e_mmask, e_mwdata, e_npc);

                if (nf == 15) begin
                    e_rs1_dc = ((^e_rs1a) === 1'bx) || ((^e_rs1d) === 1'bx);
                    e_rs2_dc = ((^e_rs2a) === 1'bx) || ((^e_rs2d) === 1'bx);

                    // check our own setup before blaming the design: the
                    // word the trace says runs at this pc has to be the word
                    // the memory model actually holds there
                    if (imem_b[e_pc[16:2]] !== e_inst) begin
                        setup_errors = setup_errors + 1;
                        $display("[SETUP] program image does not match the trace at vector %0d:",
                                 vec + 1);
                        $display("           pc=%h  imem holds %h, trace says %h",
                                 e_pc, imem_b[e_pc[16:2]], e_inst);
                        $display("         This is a testbench/setup problem (wrong or stale");
                        $display("         hart_program.hex), not a bug in hart.v.");
                        trace_done = 1;
                    end else begin
                        vec = vec + 1;
                        if (cur_group >= 0) gtotal[cur_group] = gtotal[cur_group] + 1;

                        @(posedge clk);
                        sample_b;

                        step_bad = 1'b0;
                        run_checks(MODE_COUNT);

                        if (!step_bad) begin
                            passed     = passed + 1;
                            vec_passed = vec_passed + 1;
                            if (cur_group >= 0) gpassed[cur_group] = gpassed[cur_group] + 1;
                        end else begin
                            failed     = failed + 1;
                            vec_failed = vec_failed + 1;
                            // the first 20 failures print in full, with the
                            // sim time so the spot is findable in gtkwave
                            if (reported < MAX_REPORTED) begin
                                reported = reported + 1;
                                $display("[FAIL] vector %0d (%0s): pc=%h inst=%h t=%0t",
                                         vec,
                                         (cur_group >= 0) ? gname[cur_group] : "?",
                                         e_pc, e_inst, $time);
                                run_checks(MODE_PRINT);
                                if (reported == MAX_REPORTED) begin
                                    $display("");
                                    $display("... further failing vectors are counted but not printed.");
                                    $display("    The trace is one continuous execution: a wrong branch");
                                    $display("    or jump target fetches a different instruction for");
                                    $display("    every vector after it, so most of what follows is");
                                    $display("    usually downstream of the FIRST failure above. Fix");
                                    $display("    that one and re-run before reading any of the rest.");
                                    $display("");
                                end
                            end
                        end
                    end
                end else begin
                    ng = $sscanf(line, "# --- %s", grp);
                    if (ng == 1) begin
                        if (ngroups < MAX_GROUPS) begin
                            gname[ngroups] = grp;
                            cur_group      = ngroups;
                            ngroups        = ngroups + 1;
                        end
                    end
                    // anything else is a comment or a blank line
                end
            end
        end

        $fclose(trace_fd);

        @(negedge clk);
        rst_b = 1'b1;

        // summary and verdict
        $display("");
        $display("---------- trace summary ----------");
        $display("vectors: %0d   passed: %0d   failed: %0d", vec, vec_passed, vec_failed);
        for (i = 0; i < ngroups; i = i + 1) begin
            $display("  %0s %0d/%0d %0s",
                     pad24(gname[i]), gpassed[i], gtotal[i],
                     (gpassed[i] == gtotal[i]) ? "ok" : "<-- FAIL");
        end

        $display("");
        $display("mismatches by trace column:");
        nlisted = 0;
        for (i = 0; i < FIRST_RULE; i = i + 1)
            if (fmiss[i] != 0) begin
                $display("  %0s: %0d", fname(i), fmiss[i]);
                nlisted = nlisted + 1;
            end
        if (nlisted == 0) $display("  (none)");

        $display("mismatches by spec rule (what the trace leaves as don't-care):");
        nlisted = 0;
        for (i = FIRST_RULE; i < NFIELD; i = i + 1)
            if (fmiss[i] != 0) begin
                $display("  %0s: %0d", fname(i), fmiss[i]);
                nlisted = nlisted + 1;
            end
        if (nlisted == 0) $display("  (none)");

        // one marker per failing group, in the form the course graders parse
        // for: a plain [GROUP.NAME FAILURE] substring, the way phase 2's
        // official alu_tb.v and decoder_tb.v emit it. the names are the ones
        // the autograder reports, so a marker here points at the same kind of
        // check that will fail there
        for (i = 0; i < ngroups; i = i + 1)
            if (gpassed[i] != gtotal[i]) $display("[%0s FAILURE]", gname[i]);

        report_verdict;
        $finish;
    end

endmodule

`default_nettype wire
