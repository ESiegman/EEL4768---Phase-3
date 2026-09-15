`timescale 1ns / 1ps `default_nettype none

// Self-checking testbench for the `rf` register file.
//
// Two things shape this file:
//
//   1. `rf` is parameterized, and the graders run it in both configurations
//      (rf #(0) and rf #(1), positionally). The local runner only picks up one
//      rf_tb.v, so both configurations are instantiated here side by side on
//      identical stimulus. Every bypass check compares the two against
//      *different* expected values -- that difference is the whole feature.
//
//   2. Reads are combinational but writes are synchronous, so *when* you look
//      is half of each assertion. The convention throughout: drive inputs on
//      the falling edge, and look at outputs after a `#1` settle. Sampling
//      directly on @(posedge clk) races the nonblocking write update.
//
// Expected values come from the phase 2 specification, Section 6.1 -- never
// from rf.v. A model read out of the design under test only proves the design
// agrees with itself.
module rf_tb;

  // ---------------------------------------------------------------------
  // 1. Signals: reg drives an input, wire observes an output.
  // ---------------------------------------------------------------------
  reg            clk;
  reg            rst;
  reg     [ 4:0] rs1_addr;
  reg     [ 4:0] rs2_addr;
  reg            wen;
  reg     [ 4:0] waddr;
  reg     [31:0] wdata;

  // `nb` = the BYPASS_EN = 0 instance, `by` = the BYPASS_EN = 1 instance.
  wire    [31:0] nb_rs1;
  wire    [31:0] nb_rs2;
  wire    [31:0] by_rs1;
  wire    [31:0] by_rs2;

  integer        passed;
  integer        failed;
  integer        i;
  integer        k;
  integer        errors;
  integer        seed;

  reg     [31:0] rnd;

  // ---------------------------------------------------------------------
  // 2. The two devices under test.
  //
  //    The parameter is passed positionally, as #(0) / #(1), because that is
  //    how the graders instantiate rf -- so this also checks that BYPASS_EN
  //    is still the first parameter in the port list. Ports are connected by
  //    name, which positional connection would silently break the moment
  //    someone reorders them.
  // ---------------------------------------------------------------------
  rf #(0) dut_nb (
      .i_clk      (clk),
      .i_rst      (rst),
      .i_rs1_raddr(rs1_addr),
      .o_rs1_rdata(nb_rs1),
      .i_rs2_raddr(rs2_addr),
      .o_rs2_rdata(nb_rs2),
      .i_rd_wen   (wen),
      .i_rd_waddr (waddr),
      .i_rd_wdata (wdata)
  );

  rf #(1) dut_by (
      .i_clk      (clk),
      .i_rst      (rst),
      .i_rs1_raddr(rs1_addr),
      .o_rs1_rdata(by_rs1),
      .i_rs2_raddr(rs2_addr),
      .o_rs2_rdata(by_rs2),
      .i_rd_wen   (wen),
      .i_rd_waddr (waddr),
      .i_rd_wdata (wdata)
  );

  // Rising edges at t = 5, 15, 25, ... falling edges at t = 10, 20, 30, ...
  initial clk = 1'b0;
  always #5 clk = ~clk;

  // ---------------------------------------------------------------------
  // A reference model of the register file, written from Section 6.1 of the
  // specification. The random test at the bottom checks both DUTs against it.
  // ---------------------------------------------------------------------
  reg [31:0] model[0:31];

  always @(posedge clk) begin
    if (rst) begin
      for (k = 0; k < 32; k = k + 1) model[k] <= 32'b0;
    end else if (wen && waddr != 5'd0) begin
      // A write to x0 is discarded, so x0 never enters the array.
      model[waddr] <= wdata;
    end
  end

  // What a read port should be showing right now, for a given bypass setting.
  function [31:0] model_read;
    input [4:0] addr;
    input bypass;
    begin
      if (addr == 5'd0) model_read = 32'b0;
      else if (bypass && wen && waddr == addr) model_read = wdata;
      else model_read = model[addr];
    end
  endfunction

  // ---------------------------------------------------------------------
  // 3. Comparison helpers.
  //
  //    `===` rather than `==` on purpose: it compares x and z literally, so
  //    an undriven output fails here instead of quietly comparing "unknown"
  //    and returning unknown. (The no-=== rule in Section 3 of the spec
  //    applies to the synthesizable submission files, not to testbenches.)
  //
  //    The label reg is 128 characters. A string literal wider than the reg
  //    holding it loses its *leading* characters, silently.
  // ---------------------------------------------------------------------
  task expect_eq;
    input [1023:0] label;
    input [31:0] got;
    input [31:0] exp;
    begin
      if (got === exp) begin
        passed = passed + 1;
        $display("[PASS] %0s", label);
      end else begin
        failed = failed + 1;
        $display("[FAIL] %0s", label);
        $display("         got %h, expected %h  (t=%0t)", got, exp, $time);
      end
    end
  endtask

  // Point both read ports somewhere and let the combinational path settle.
  // No clock edge is involved -- that is the point of an asynchronous read.
  task set_read;
    input [4:0] a1;
    input [4:0] a2;
    begin
      rs1_addr = a1;
      rs2_addr = a2;
      #1;
    end
  endtask

  // One complete write transaction: set up on the falling edge, commit on the
  // rising edge, then drop write enable so it does not repeat.
  task write_reg;
    input [4:0] addr;
    input [31:0] data;
    begin
      @(negedge clk);
      wen   = 1'b1;
      waddr = addr;
      wdata = data;
      @(posedge clk);
      #1;
      wen = 1'b0;
    end
  endtask

  // Advance one clock with the write port idle.
  task idle_edge;
    begin
      @(negedge clk);
      wen = 1'b0;
      @(posedge clk);
      #1;
    end
  endtask

  task do_reset;
    begin
      @(negedge clk);
      rst = 1'b1;
      wen = 1'b0;
      @(posedge clk);
      #1;
      @(negedge clk);
      rst = 1'b0;
      #1;
    end
  endtask

  // Read every register on every port of both DUTs and expect zero. Reported
  // as one line rather than 128, so a clean run stays readable.
  task expect_all_zero;
    input [1023:0] label;
    begin
      errors = 0;
      for (k = 0; k < 32; k = k + 1) begin
        rs1_addr = k[4:0];
        rs2_addr = k[4:0];
        #1;
        if (nb_rs1 !== 32'b0 || nb_rs2 !== 32'b0 || by_rs1 !== 32'b0 || by_rs2 !== 32'b0) begin
          errors = errors + 1;
          $display("         x%0d: nb=%h/%h by=%h/%h", k, nb_rs1, nb_rs2, by_rs1, by_rs2);
        end
      end
      if (errors == 0) begin
        passed = passed + 1;
        $display("[PASS] %0s", label);
      end else begin
        failed = failed + 1;
        $display("[FAIL] %0s: %0d of 32 registers were not zero", label, errors);
      end
    end
  endtask

  // ---------------------------------------------------------------------
  // 4. The test program.
  // ---------------------------------------------------------------------
  initial begin
    // The runner cd's into build/ before running vvp, so this lands at
    // build/rf.vcd. Open it with `gtkwave build/rf.vcd`.
    $dumpfile("rf.vcd");
    $dumpvars(0, rf_tb);

    passed   = 0;
    failed   = 0;
    rst      = 1'b0;
    wen      = 1'b0;
    waddr    = 5'd0;
    wdata    = 32'd0;
    rs1_addr = 5'd0;
    rs2_addr = 5'd0;

    $display("========== rf testbench ==========");

    // --- Reset ---------------------------------------------------------
    $display("--- reset ---");
    do_reset;
    expect_all_zero("reset clears all 32 registers");

    // --- x0 is hardwired to zero ---------------------------------------
    // The spec calls this out as the graders' very first check.
    $display("--- x0 hardwired to zero ---");
    write_reg(5'd0, 32'hDEAD_BEEF);
    set_read(5'd0, 5'd0);
    expect_eq("no-bypass: x0 reads 0 on port 1 after a write to it", nb_rs1, 32'b0);
    expect_eq("no-bypass: x0 reads 0 on port 2 after a write to it", nb_rs2, 32'b0);
    expect_eq("bypass:    x0 reads 0 on port 1 after a write to it", by_rs1, 32'b0);
    expect_eq("bypass:    x0 reads 0 on port 2 after a write to it", by_rs2, 32'b0);

    // x0 must stay zero even with the write still in flight. The spec's
    // bypass clause excludes x0 explicitly, and it is easy to forward x0 by
    // accident when the bypass mux is written before the x0 mux.
    @(negedge clk);
    wen   = 1'b1;
    waddr = 5'd0;
    wdata = 32'hDEAD_BEEF;
    set_read(5'd0, 5'd0);
    expect_eq("no-bypass: x0 stays 0 with a write to x0 in flight", nb_rs1, 32'b0);
    expect_eq("bypass:    x0 is NOT forwarded, stays 0", by_rs1, 32'b0);
    expect_eq("bypass:    x0 is NOT forwarded on port 2 either", by_rs2, 32'b0);
    @(posedge clk);
    #1;
    wen = 1'b0;
    set_read(5'd0, 5'd0);
    expect_eq("no-bypass: x0 still 0 after the edge", nb_rs1, 32'b0);
    expect_eq("bypass:    x0 still 0 after the edge", by_rs1, 32'b0);

    // --- Basic write and read ------------------------------------------
    $display("--- write then read ---");
    write_reg(5'd7, 32'hCAFE_BABE);
    set_read(5'd7, 5'd0);
    expect_eq("no-bypass: x7 holds the value written to it", nb_rs1, 32'hCAFE_BABE);
    expect_eq("bypass:    x7 holds the value written to it", by_rs1, 32'hCAFE_BABE);

    write_reg(5'd7, 32'h0BAD_F00D);
    set_read(5'd7, 5'd0);
    expect_eq("no-bypass: a second write overwrites x7", nb_rs1, 32'h0BAD_F00D);
    expect_eq("bypass:    a second write overwrites x7", by_rs1, 32'h0BAD_F00D);

    // --- The two read ports are independent -----------------------------
    $display("--- independent read ports ---");
    write_reg(5'd12, 32'h1111_2222);
    write_reg(5'd19, 32'h3333_4444);

    set_read(5'd12, 5'd19);
    expect_eq("no-bypass: port 1 reads x12 while port 2 reads x19", nb_rs1, 32'h1111_2222);
    expect_eq("no-bypass: port 2 reads x19 while port 1 reads x12", nb_rs2, 32'h3333_4444);

    // Swapped, to catch a port-1 result wired to both outputs.
    set_read(5'd19, 5'd12);
    expect_eq("no-bypass: the ports swap independently, port 1", nb_rs1, 32'h3333_4444);
    expect_eq("no-bypass: the ports swap independently, port 2", nb_rs2, 32'h1111_2222);

    set_read(5'd12, 5'd12);
    expect_eq("no-bypass: both ports may read the same register, p1", nb_rs1, 32'h1111_2222);
    expect_eq("no-bypass: both ports may read the same register, p2", nb_rs2, 32'h1111_2222);

    // --- Reads are combinational ----------------------------------------
    // Three different addresses, three different results, no clock edge
    // anywhere between them.
    $display("--- reads are asynchronous ---");
    set_read(5'd7, 5'd0);
    expect_eq("async: x7 with no intervening clock edge", nb_rs1, 32'h0BAD_F00D);
    set_read(5'd12, 5'd0);
    expect_eq("async: x12 in the same cycle, still no edge", nb_rs1, 32'h1111_2222);
    set_read(5'd19, 5'd0);
    expect_eq("async: x19 in the same cycle, still no edge", nb_rs1, 32'h3333_4444);

    // --- Write enable low ------------------------------------------------
    $display("--- write enable low ---");
    @(negedge clk);
    wen   = 1'b0;
    waddr = 5'd12;
    wdata = 32'hFFFF_FFFF;  // present on the bus, but must not be written
    set_read(5'd12, 5'd0);
    expect_eq("no-bypass: wen low, no forwarding either", nb_rs1, 32'h1111_2222);
    expect_eq("bypass:    wen low, so nothing is forwarded", by_rs1, 32'h1111_2222);
    @(posedge clk);
    #1;
    set_read(5'd12, 5'd0);
    expect_eq("no-bypass: wen low leaves x12 unchanged at the edge", nb_rs1, 32'h1111_2222);
    expect_eq("bypass:    wen low leaves x12 unchanged at the edge", by_rs1, 32'h1111_2222);

    // --- Bypass ----------------------------------------------------------
    // The core of the feature: one in-flight write, observed before the edge,
    // must read differently in the two configurations.
    $display("--- bypass on an in-flight write ---");
    @(negedge clk);
    wen   = 1'b1;
    waddr = 5'd9;
    wdata = 32'h1234_5678;
    set_read(5'd9, 5'd9);
    expect_eq("no-bypass: port 1 still shows the old value pre-edge", nb_rs1, 32'b0);
    expect_eq("no-bypass: port 2 still shows the old value pre-edge", nb_rs2, 32'b0);
    expect_eq("bypass:    port 1 forwards the write data pre-edge", by_rs1, 32'h1234_5678);
    expect_eq("bypass:    port 2 forwards the write data pre-edge", by_rs2, 32'h1234_5678);
    @(posedge clk);
    #1;
    wen = 1'b0;
    set_read(5'd9, 5'd9);
    expect_eq("no-bypass: x9 is visible after the edge", nb_rs1, 32'h1234_5678);
    expect_eq("bypass:    x9 is visible after the edge too", by_rs1, 32'h1234_5678);

    // Bypass must be address-matched: a write in flight to x9 says nothing
    // about a read of x12.
    $display("--- bypass only on an address match ---");
    @(negedge clk);
    wen   = 1'b1;
    waddr = 5'd9;
    wdata = 32'hAAAA_BBBB;
    set_read(5'd12, 5'd9);
    expect_eq("bypass: a non-matching port is untouched", by_rs1, 32'h1111_2222);
    expect_eq("bypass: the matching port on the same cycle forwards", by_rs2, 32'hAAAA_BBBB);
    expect_eq("no-bypass: neither port forwards", nb_rs1, 32'h1111_2222);
    expect_eq("no-bypass: matching port shows the stored value", nb_rs2, 32'h1234_5678);
    @(posedge clk);
    #1;
    wen = 1'b0;

    // --- Boundary registers and data patterns ----------------------------
    $display("--- boundaries ---");
    write_reg(5'd1, 32'hFFFF_FFFF);
    write_reg(5'd31, 32'h8000_0001);
    set_read(5'd1, 5'd31);
    expect_eq("x1 (lowest writable register) holds all ones", nb_rs1, 32'hFFFF_FFFF);
    expect_eq("x31 (highest register) holds its value", nb_rs2, 32'h8000_0001);

    write_reg(5'd31, 32'h0000_0000);
    set_read(5'd31, 5'd1);
    expect_eq("x31 can be written back to zero", nb_rs1, 32'b0);
    expect_eq("x1 is undisturbed by the write to x31", nb_rs2, 32'hFFFF_FFFF);

    // --- Reset is synchronous --------------------------------------------
    // x1 still holds all ones here. Asserting reset must change nothing until
    // the rising edge -- an asynchronous reset fails the first check below.
    $display("--- reset is synchronous ---");
    @(negedge clk);
    rst = 1'b1;
    wen = 1'b0;
    set_read(5'd1, 5'd12);
    expect_eq("rst high but pre-edge: x1 is unchanged", nb_rs1, 32'hFFFF_FFFF);
    expect_eq("rst high but pre-edge: x12 is unchanged", nb_rs2, 32'h1111_2222);
    @(posedge clk);
    #1;
    set_read(5'd1, 5'd12);
    expect_eq("rst takes effect on the rising edge: x1", nb_rs1, 32'b0);
    expect_eq("rst takes effect on the rising edge: x12", nb_rs2, 32'b0);
    @(negedge clk);
    rst = 1'b0;
    #1;
    expect_all_zero("reset cleared every register, not just the two read");

    // Reset and a write arriving on the same edge. The spec puts reset "inside
    // the same clocked block as the write", which gives reset priority; the
    // register must come out of the edge cleared, not written.
    $display("--- reset priority over a simultaneous write ---");
    write_reg(5'd5, 32'hA5A5_A5A5);
    set_read(5'd5, 5'd0);
    expect_eq("x5 is written before the priority check", nb_rs1, 32'hA5A5_A5A5);

    @(negedge clk);
    rst   = 1'b1;
    wen   = 1'b1;
    waddr = 5'd5;
    wdata = 32'h5A5A_5A5A;
    @(posedge clk);
    #1;
    rst = 1'b0;
    wen = 1'b0;
    set_read(5'd5, 5'd0);
    expect_eq("no-bypass: reset wins over a same-edge write", nb_rs1, 32'b0);
    expect_eq("bypass:    reset wins over a same-edge write", by_rs1, 32'b0);

    // --- Random cross-check against the model -----------------------------
    // A fixed seed keeps the run reproducible: a failure you see once is a
    // failure you can see again. Reset stays deasserted here -- whether the
    // combinational bypass path is suppressed during reset is not something
    // the spec pins down, so the directed tests above cover reset instead of
    // asserting a behavior a defensible implementation might not have.
    $display("--- random ---");
    do_reset;
    for (k = 0; k < 32; k = k + 1) model[k] = 32'b0;

    seed   = 32'd12345;
    errors = 0;
    for (i = 0; i < 200; i = i + 1) begin
      @(negedge clk);
      rnd      = $random(seed);
      wen      = rnd[0];
      rnd      = $random(seed);
      waddr    = rnd[4:0];
      wdata    = $random(seed);
      rnd      = $random(seed);
      rs1_addr = rnd[4:0];
      rnd      = $random(seed);
      rs2_addr = rnd[4:0];
      #1;

      if (nb_rs1 !== model_read(
              rs1_addr, 1'b0
          ) || nb_rs2 !== model_read(
              rs2_addr, 1'b0
          ) || by_rs1 !== model_read(
              rs1_addr, 1'b1
          ) || by_rs2 !== model_read(
              rs2_addr, 1'b1
          )) begin
        errors = errors + 1;
        failed = failed + 1;
        $display("[FAIL] random %0d: wen=%b waddr=x%0d wdata=%h rs1=x%0d rs2=x%0d", i, wen, waddr,
                 wdata, rs1_addr, rs2_addr);
        $display("         nb: %h/%h (expected %h/%h)", nb_rs1, nb_rs2, model_read(rs1_addr, 1'b0),
                 model_read(rs2_addr, 1'b0));
        $display("         by: %h/%h (expected %h/%h)", by_rs1, by_rs2, model_read(rs1_addr, 1'b1),
                 model_read(rs2_addr, 1'b1));
      end else begin
        passed = passed + 1;
      end

      @(posedge clk);
      #1;
    end
    wen = 1'b0;
    $display("       200 random cycles checked against the model, %0d mismatched", errors);

    // --- Verdict ---------------------------------------------------------
    $display("==================================");
    $display("%0d passed, %0d failed", passed, failed);
    if (failed == 0) $display("ALL TESTS PASSED");
    else $display("TEST FAILED");

    // Without $finish the simulation runs forever and vvp never returns.
    $finish;
  end

endmodule

`default_nettype wire
