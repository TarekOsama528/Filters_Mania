`timescale 1ns/1ps

// =============================================================================
// Simple Testbench for lms_adaptive_filter
// Checks y output against manually computed expected values
//
// Parameters: N=4, INTEGER_BITS=4, FRACTIONAL_BITS=8  → Q3.8 (12-bit)
// Scale factor = 2^8 = 256
//
// Test scenario:
//   mu   = 0.5   → 0.5  * 256 = 128
//   x    = 1.0   → 1.0  * 256 = 256  (constant input each cycle)
//   d    = 2.0   → 2.0  * 256 = 512  (desired output)
//   w[i] = 0.0 initially
//
// Expected y per cycle (weights start at 0, converge toward d):
//   cycle 1: y = 0               (weights still 0)
//   cycle 2: y grows as weights update
// =============================================================================

module tb_lms;

    localparam int N               = 4;
    localparam int FRACTIONAL_BITS = 8;
    localparam int INTEGER_BITS    = 4;
    localparam int NB              = INTEGER_BITS + FRACTIONAL_BITS;  // 12
    localparam real SCALE          = 2.0 ** FRACTIONAL_BITS;          // 256.0
    localparam real TOL            = 2.0 / SCALE;                     // 2 LSBs

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    logic clk = 0;
    logic rst_n;
    logic signed [NB-1:0] x, d, mu;
    logic signed [NB-1:0] y, e;
    logic                  valid;

    int pass_cnt = 0, fail_cnt = 0;

    // -------------------------------------------------------------------------
    // DUT
    // -------------------------------------------------------------------------
    lms_adaptive_filter #(
        .N               (N),
        .FRACTIONAL_BITS (FRACTIONAL_BITS),
        .INTEGER_BITS    (INTEGER_BITS)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .x(x), .d(d), .mu(mu),
        .y(y), .e(e), .valid(valid)
    );

    always #5 clk = ~clk;   // 100 MHz

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------
    function automatic logic signed [NB-1:0] fx(real v);
        return NB'(int'(v * SCALE));
    endfunction

    function automatic real fl(logic signed [NB-1:0] v);
        return real'(signed'(v)) / SCALE;
    endfunction

    // Wait for valid pulse (one full FSM cycle = 4 clocks)
    task wait_valid();
        @(posedge clk iff valid); #1;
    endtask

    // Check y against expected float value
    task check_y(string label, real exp_real);
        real got, err;
        got = fl(y);
        err = (got > exp_real) ? got - exp_real : exp_real - got;
        if (err <= TOL) begin
            pass_cnt++;
            $display("  PASS %-25s | y=%7.4f  exp=%7.4f", label, got, exp_real);
        end else begin
            fail_cnt++;
            $display("  FAIL %-25s | y=%7.4f  exp=%7.4f  err=%e <<<",
                     label, got, exp_real, err);
        end
    endtask

    // -------------------------------------------------------------------------
    // Golden model (mirrors RTL sign-LMS exactly)
    // -------------------------------------------------------------------------
    real gw [N];
    real gx  [N];
    real gy, ge;
    real gmu;

    task golden_reset();
        for (int i = 0; i < N; i++) begin gw[i] = 0.0; gx[i] = 0.0; end
        gy = 0.0; ge = 0.0;
    endtask

    // Run one LMS cycle in float, return expected y
    function automatic real golden_cycle(real x_in, real d_in, real mu_in);
        real acc, e_val;
        // SHIFT
        for (int i = N-1; i > 0; i--) gx[i] = gx[i-1];
        gx[0] = x_in;
        // COMPUTE
        acc = 0.0;
        for (int i = 0; i < N; i++) acc += gw[i] * gx[i];
        gy  = acc;
        ge  = d_in - gy;
        // UPDATE_W — sign-LMS
        for (int i = 0; i < N; i++) begin
            if (ge < 0)
                gw[i] = gw[i] - 2.0 * mu_in * gx[i];
            else
                gw[i] = gw[i] + 2.0 * mu_in * gx[i];
        end
        return gy;
    endfunction

    // =========================================================================
    // TESTS
    // =========================================================================
    real exp_y;

    initial begin
        $display("=========================================");
        $display(" LMS Adaptive Filter Testbench");
        $display(" N=%0d  Q%0d.%0d  TOL=2 LSBs", N, INTEGER_BITS-1, FRACTIONAL_BITS);
        $display("=========================================");

        // Setup inputs
        mu = fx(0.5);     // step size = 0.5
        x  = fx(1.0);     // constant input = 1.0
        d  = fx(2.0);     // desired output = 2.0
        gmu = 0.5;

        // ------------------------------------------------------------------
        // TEST 1: Reset — y must be 0 while rst_n=0
        // ------------------------------------------------------------------
        $display("\n[TEST 1] Reset");
        rst_n = 0;
        repeat(4) @(posedge clk); #1;
        if (y === '0) begin
            pass_cnt++;
            $display("  PASS y=0 during reset");
        end else begin
            fail_cnt++;
            $display("  FAIL y=%0d during reset  <<<", signed'(y));
        end

        // Release reset
        rst_n = 1;
        golden_reset();
        @(posedge clk); #1;

        // ------------------------------------------------------------------
        // TEST 2: First output — weights are all 0 so y must be 0
        // ------------------------------------------------------------------
        $display("\n[TEST 2] First cycle (weights=0, expect y=0)");
        wait_valid();
        exp_y = golden_cycle(1.0, 2.0, gmu);
        check_y("cycle 1 y=0", exp_y);

        // ------------------------------------------------------------------
        // TEST 3: Several cycles — y converges toward d=2.0
        // Check RTL matches golden each cycle
        // ------------------------------------------------------------------
        $display("\n[TEST 3] Convergence (x=1.0, d=2.0, mu=0.5)");
        for (int c = 2; c <= 8; c++) begin
            wait_valid();
            exp_y = golden_cycle(1.0, 2.0, gmu);
            check_y($sformatf("cycle %0d", c), exp_y);
        end

        // ------------------------------------------------------------------
        // TEST 4: Change desired signal mid-run — filter re-adapts
        // ------------------------------------------------------------------
        $display("\n[TEST 4] Change d to -1.0, filter re-adapts");
        d = fx(-1.0);
        for (int c = 1; c <= 6; c++) begin
            wait_valid();
            exp_y = golden_cycle(1.0, -1.0, gmu);
            check_y($sformatf("re-adapt cycle %0d", c), exp_y);
        end

        // ------------------------------------------------------------------
        // TEST 5: Zero input — y must go to 0 regardless of weights
        // ------------------------------------------------------------------
        $display("\n[TEST 5] Zero input (x=0, y must be 0)");
        x = '0; d = fx(2.0);
        for (int c = 1; c <= 4; c++) begin
            wait_valid();
            exp_y = golden_cycle(0.0, 2.0, gmu);
            check_y($sformatf("zero_x cycle %0d", c), exp_y);
        end

        // ------------------------------------------------------------------
        // Summary
        // ------------------------------------------------------------------
        $display("\n=========================================");
        $display(" PASS: %0d   FAIL: %0d   TOTAL: %0d",
            pass_cnt, fail_cnt, pass_cnt + fail_cnt);
        $display("=========================================");
        $finish;
    end

endmodule