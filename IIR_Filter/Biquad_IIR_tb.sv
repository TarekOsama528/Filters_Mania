`timescale 1ns/1ps

// =============================================================================
// Biquad IIR Filter Testbench
// =============================================================================
//
// DUT: biquad_iir — Direct Form II Transposed
//
// Fixed-point format:
//   x, y   → Q16.16  (32-bit signed)
//   coeffs → Q16.16  (32-bit signed)
//
// RTL sign convention:
//   b2_a2 = x*b2 - y*a2   (a2 passed as positive)
//   b1_a1 = x*b1 - y*a1   (a1 passed as negative)
//
// Golden model mirrors RTL exactly:
//   w2[n] = b2*x[n] - a2*y[n-1]            (registered — uses old w2)
//   w1[n] = b1*x[n] - a1*y[n-1] + w2[n-1] (registered — uses old w2)
//   y[n]  = b0*x[n] + w1[n-1]
//
// Golden feeds quantized RTL y back each cycle to prevent drift.
//
// Coefficients: LPF Butterworth fc=8kHz fs=48kHz
//   fc=1kHz poles are too close to unit circle and become
//   unstable after Q16.16 quantization. fc=8kHz is safe (pole mag ≈ 0.49).
//
// Tests:
//   1. Reset            — y=0 while rst_n=0
//   2. Zero input       — y stays 0 with x=0
//   3. All-pass         — b0=1, rest=0 → y[n] = x[n-1]
//   4. Impulse response — x[0]=1 then zeros, verify h[n] decays
//   5. Step response    — x=1 forever, verify y converges
//   6. Saturation MAX   — huge positive input → y clamps to MAX_POS
//   7. Saturation MIN   — huge negative input → y clamps to MIN_NEG
//   8. Mid-run reset    — assert reset mid-stream, state must clear
// =============================================================================

module tb_biquad_iir;

    // =========================================================================
    // Parameters & signals
    // =========================================================================
    localparam int  IFP     = 16;
    localparam int  IIP     = 16;
    localparam int  CFP     = 16;
    localparam int  CIP     = 16;
    localparam int  NX      = IIP + IFP;
    localparam int  NC      = CIP + CFP;
    localparam real SCALE_X = 2.0 ** IFP;
    localparam real SCALE_C = 2.0 ** CFP;
    localparam real MAX_POS = (2.0**(IIP-1) - 2.0**(-IFP));
    localparam real MIN_NEG = -(2.0**(IIP-1));
    localparam real TOL     = 2.5 / SCALE_X;   // 2.5 LSBs

    logic clk = 0;
    logic rst_n;
    logic signed [NX-1:0] x, y;
    logic signed [NC-1:0] b0, b1, b2, a1, a2;

    int pass_cnt = 0, fail_cnt = 0;

    // =========================================================================
    // DUT
    // =========================================================================
    biquad_iir #(
        .INPUT_FRACTIONAL_PART (IFP), .INPUT_INTEGER_PART    (IIP),
        .COEFF_FRACTIONAL_PART (CFP), .COEFF_INTEGER_PART    (CIP)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .x(x),  .y(y),
        .b0(b0), .b1(b1), .b2(b2),
        .a1(a1), .a2(a2)
    );

    always #5 clk = ~clk;   // 100 MHz

    // =========================================================================
    // Fixed-point helpers
    // =========================================================================
    function automatic logic signed [NX-1:0] fx(real v);
        return NX'(longint'(v * SCALE_X));
    endfunction

    function automatic logic signed [NC-1:0] fc(real v);
        return NC'(longint'(v * SCALE_C));
    endfunction

    function automatic real fl(logic signed [NX-1:0] v);
        return real'(signed'(v)) / SCALE_X;
    endfunction

    // =========================================================================
    // Golden model
    // =========================================================================
    real gw1, gw2;
    real gb0, gb1, gb2, ga1, ga2;

    // One golden cycle. y_q = quantized RTL y from previous cycle.
    function automatic real golden(real x_r, real y_q);
        real yn, w1n, w2n;
        yn  = gb0 * x_r + gw1;
        w1n = gb1 * x_r - ga1 * y_q + gw2;
        w2n = gb2 * x_r - ga2 * y_q;
        if (yn > MAX_POS) yn = MAX_POS;
        if (yn < MIN_NEG) yn = MIN_NEG;
        gw1 = w1n;
        gw2 = w2n;
        return yn;
    endfunction

    task reset_golden();
        gw1 = 0.0; gw2 = 0.0;
    endtask

    // =========================================================================
    // Coefficient loading
    // =========================================================================
    task load_lpf();
        // Butterworth LPF fc=8kHz fs=48kHz — stable at Q16.16
        b0 = fc( 0.155045); gb0 =  0.155045;
        b1 = fc( 0.310089); gb1 =  0.310089;
        b2 = fc( 0.155045); gb2 =  0.155045;
        a1 = fc(-0.620163); ga1 = -0.620163;
        a2 = fc( 0.240341); ga2 =  0.240341;
    endtask

    task load_allpass();
        b0 = fc(1.0); gb0 = 1.0;
        b1 = fc(0.0); gb1 = 0.0;
        b2 = fc(0.0); gb2 = 0.0;
        a1 = fc(0.0); ga1 = 0.0;
        a2 = fc(0.0); ga2 = 0.0;
    endtask

    // =========================================================================
    // Reset helper
    // =========================================================================
    task do_reset();
        rst_n = 0; x = '0;
        repeat(2) @(posedge clk); #1;
        rst_n = 1;
        reset_golden();
        @(posedge clk); #1;
    endtask

    // =========================================================================
    // Check tasks
    // =========================================================================

    // Drive x, clock one cycle, compare y vs golden
    // y_prev: RTL y from LAST cycle (fed into golden to match RTL feedback)
    task check(string label, real x_r, real y_prev);
        real got, exp_v, err;
        x = fx(x_r);
        @(posedge clk); #1;
        got   = fl(y);
        exp_v = golden(x_r, y_prev);
        err   = (got > exp_v) ? got - exp_v : exp_v - got;
        if (err <= TOL) begin
            pass_cnt++;
            $display("  PASS %-30s | x=%7.4f  y=%10.6f  exp=%10.6f",
                     label, x_r, got, exp_v);
        end else begin
            fail_cnt++;
            $display("  FAIL %-30s | x=%7.4f  y=%10.6f  exp=%10.6f  err=%e <<<",
                     label, x_r, got, exp_v, err);
        end
    endtask

    // Check y equals exact bit pattern (for reset / saturation)
    task check_exact(string label, logic signed [NX-1:0] expected);
        if (y === expected) begin
            pass_cnt++;
            $display("  PASS %-30s | y = %0d", label, signed'(y));
        end else begin
            fail_cnt++;
            $display("  FAIL %-30s | y = %0d  expected = %0d <<<",
                     label, signed'(y), signed'(expected));
        end
    endtask

    // =========================================================================
    // Test variables (declared at module level — no automatic inside initial)
    // =========================================================================
    real yp;   // previous RTL y, used to feed golden

    // =========================================================================
    // TESTS
    // =========================================================================
    initial begin
        $display("=========================================");
        $display(" Biquad IIR Filter Testbench");
        $display(" Format  : Q%0d.%0d   TOL = 2.5 LSBs", IIP-1, IFP);
        $display(" Coeffs  : LPF Butterworth fc=8kHz fs=48kHz");
        $display("=========================================");

        // -----------------------------------------------------------------
        // TEST 1: Reset
        // Drive x=1.0 while rst_n=0 — y must stay 0
        // -----------------------------------------------------------------
        $display("\n[TEST 1] Reset");
        load_lpf();
        rst_n = 0;
        x = fx(1.0);
        @(posedge clk); #1;
        check_exact("y=0 while rst_n=0", '0);
        rst_n = 1;
        reset_golden();

        // -----------------------------------------------------------------
        // TEST 2: Zero input
        // After reset, x=0 must keep y=0 (no phantom output)
        // -----------------------------------------------------------------
        $display("\n[TEST 2] Zero input");
        load_lpf();
        do_reset();
        x = '0; @(posedge clk); #1; check_exact("cycle 1: y=0", '0);
        x = '0; @(posedge clk); #1; check_exact("cycle 2: y=0", '0);
        x = '0; @(posedge clk); #1; check_exact("cycle 3: y=0", '0);

        // -----------------------------------------------------------------
        // TEST 3: All-pass (b0=1, b1=b2=a1=a2=0)
        // y[n] must equal x[n-1] — pure 1-cycle delay
        // -----------------------------------------------------------------
        $display("\n[TEST 3] All-pass (b0=1, rest=0)");
        load_allpass();
        do_reset();
        yp = 0.0;
        check("x= 0.50 → y should be 0.00",  0.50, yp); yp = fl(y);
        check("x=-0.25 → y should be 0.50", -0.25, yp); yp = fl(y);
        check("x= 0.75 → y should be -0.25", 0.75, yp); yp = fl(y);
        check("x=-1.00 → y should be 0.75", -1.00, yp); yp = fl(y);
        check("x= 0.00 → y should be -1.00", 0.00, yp); yp = fl(y);

        // -----------------------------------------------------------------
        // TEST 4: Impulse response  (x[0]=1, x[n>0]=0)
        // h[0] = b0, then output must decay smoothly
        // -----------------------------------------------------------------
        $display("\n[TEST 4] Impulse response");
        load_lpf();
        do_reset();
        yp = 0.0;
        check("h[0]  x=1 (impulse)",  1.0, yp); yp = fl(y);
        check("h[1]  x=0",            0.0, yp); yp = fl(y);
        check("h[2]  x=0",            0.0, yp); yp = fl(y);
        check("h[3]  x=0",            0.0, yp); yp = fl(y);
        check("h[4]  x=0",            0.0, yp); yp = fl(y);
        check("h[5]  x=0",            0.0, yp); yp = fl(y);
        check("h[6]  x=0",            0.0, yp); yp = fl(y);
        check("h[7]  x=0",            0.0, yp); yp = fl(y);
        check("h[8]  x=0",            0.0, yp); yp = fl(y);
        check("h[9]  x=0",            0.0, yp); yp = fl(y);
        check("h[10] x=0",            0.0, yp); yp = fl(y);

        // -----------------------------------------------------------------
        // TEST 5: Step response  (x=1 for all cycles)
        // y must ramp up and converge to DC gain (b0+b1+b2)/(1-a1-a2)
        // -----------------------------------------------------------------
        $display("\n[TEST 5] Step response");
        load_lpf();
        do_reset();
        yp = 0.0;
        check("step[0]",  1.0, yp); yp = fl(y);
        check("step[1]",  1.0, yp); yp = fl(y);
        check("step[2]",  1.0, yp); yp = fl(y);
        check("step[3]",  1.0, yp); yp = fl(y);
        check("step[4]",  1.0, yp); yp = fl(y);
        check("step[5]",  1.0, yp); yp = fl(y);
        check("step[6]",  1.0, yp); yp = fl(y);
        check("step[7]",  1.0, yp); yp = fl(y);
        check("step[8]",  1.0, yp); yp = fl(y);
        check("step[9]",  1.0, yp); yp = fl(y);
        check("step[10]", 1.0, yp); yp = fl(y);
        check("step[11]", 1.0, yp); yp = fl(y);
        check("step[12]", 1.0, yp); yp = fl(y);
        check("step[13]", 1.0, yp); yp = fl(y);
        check("step[14]", 1.0, yp); yp = fl(y);

        // -----------------------------------------------------------------
        // TEST 6: Saturation — positive
        // MAX_POS input through all-pass → y must clamp, not wrap
        // -----------------------------------------------------------------
        $display("\n[TEST 6] Saturation — positive");
        load_allpass();
        do_reset();
        x = {1'b0, {(NX-1){1'b1}}};   // 0111...1 = MAX_POS
        @(posedge clk); #1;
        check_exact("y = MAX_POS (no wrap)", {1'b0, {(NX-1){1'b1}}});

        // -----------------------------------------------------------------
        // TEST 7: Saturation — negative
        // MIN_NEG input through all-pass → y must clamp, not wrap
        // -----------------------------------------------------------------
        $display("\n[TEST 7] Saturation — negative");
        load_allpass();
        do_reset();
        x = {1'b1, {(NX-1){1'b0}}};   // 1000...0 = MIN_NEG
        @(posedge clk); #1;
        check_exact("y = MIN_NEG (no wrap)", {1'b1, {(NX-1){1'b0}}});

        // -----------------------------------------------------------------
        // TEST 8: Mid-run reset
        // Run filter for 10 cycles to build state, then assert reset
        // → y must go to 0 immediately and stay 0
        // -----------------------------------------------------------------
        $display("\n[TEST 8] Mid-run reset");
        load_lpf();
        do_reset();
        repeat(10) begin x = fx(1.0); @(posedge clk); #1; end
        rst_n = 0;
        @(posedge clk); #1;
        check_exact("y=0 immediately after rst", '0);
        rst_n = 1;
        reset_golden();
        x = '0;
        @(posedge clk); #1;
        check_exact("y=0 after rst + x=0",      '0);

        // -----------------------------------------------------------------
        // Summary
        // -----------------------------------------------------------------
        $display("\n=========================================");
        $display(" PASS: %0d   FAIL: %0d   TOTAL: %0d",
            pass_cnt, fail_cnt, pass_cnt + fail_cnt);
        $display("=========================================");
        $finish;
    end

endmodule