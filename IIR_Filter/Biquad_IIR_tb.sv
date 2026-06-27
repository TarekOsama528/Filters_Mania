`timescale 1ns/1ps

// Testbench for biquad_iir — Direct Form II Transposed
//
// Format:
//   x, y  : Q16.16 (32-bit)
//   coeffs : Q16.16 (32-bit)
//
// Sign convention (matches RTL):
//   b2_a2 = x_b2 - y_a2   → a2 passed as POSITIVE (+0.881)
//   b1_a1 = x_b1 - y_a1   → a1 passed as NEGATIVE (-1.867)
//
// Golden equation:
//   y[n]  = b0*x[n] + w1[n-1]
//   w1[n] = b1*x[n] - a1*y[n-1] + w2[n]
//   w2[n] = b2*x[n] - a2*y[n-1]

module tb_biquad_iir;

    // ----------------------------------------------------------------
    // Parameters
    // ----------------------------------------------------------------
    localparam int IFP = 16;
    localparam int IIP = 16;
    localparam int CFP = 16;
    localparam int CIP = 16;

    localparam int NX = IIP + IFP;   // 32
    localparam int NC = CIP + CFP;   // 32

    localparam real X_SCALE     =  2.0**IFP;
    localparam real C_SCALE     =  2.0**CFP;
    localparam real MAX_POS_REAL =  (2.0**(IIP-1) - 2.0**(-IFP));
    localparam real MIN_NEG_REAL = -(2.0**(IIP-1));
    localparam real TOLERANCE   =  2.5 / X_SCALE;   // 2 LSBs

    // ----------------------------------------------------------------
    // DUT signals
    // ----------------------------------------------------------------
    logic clk, rst_n;
    logic signed [NX-1:0] x, y;
    logic signed [NC-1:0] b0, b1, b2, a1, a2;

    biquad_iir #(
        .INPUT_FRACTIONAL_PART (IFP),
        .INPUT_INTEGER_PART    (IIP),
        .COEFF_FRACTIONAL_PART (CFP),
        .COEFF_INTEGER_PART    (CIP)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .x(x), .y(y),
        .b0(b0), .b1(b1), .b2(b2),
        .a1(a1), .a2(a2)
    );

    // ----------------------------------------------------------------
    // Clock
    // ----------------------------------------------------------------
    initial clk = 0;
    always #5 clk = ~clk;

    // ----------------------------------------------------------------
    // Scoreboard
    // ----------------------------------------------------------------
    int pass_count = 0, fail_count = 0;

    // ----------------------------------------------------------------
    // Conversion helpers
    // ----------------------------------------------------------------
    function automatic logic signed [NX-1:0] to_fx_x(real v);
        return NX'(longint'(v * X_SCALE));
    endfunction

    function automatic logic signed [NC-1:0] to_fx_c(real v);
        return NC'(longint'(v * C_SCALE));
    endfunction

    function automatic real to_real_x(logic signed [NX-1:0] v);
        return real'(signed'(v)) / X_SCALE;
    endfunction

    // ----------------------------------------------------------------
    // Golden model — mirrors RTL sign convention exactly
    // ----------------------------------------------------------------
    real gld_w1, gld_w2, gld_y;
    real gb0, gb1, gb2, ga1, ga2;

    task automatic golden_reset();
        gld_w1 = 0.0; gld_w2 = 0.0; gld_y = 0.0;
    endtask

    task automatic golden_tick(real x_real);
        real y_new, w1_new, w2_new;
        y_new  = gb0 * x_real + gld_w1;                  // uses w1[n-1] (registered)
        w2_new = gb2 * x_real - ga2 * gld_y;             // w2[n] computed first (combinational in RTL)
        w1_new = gb1 * x_real - ga1 * gld_y + w2_new;   // uses w2[n] not w2[n-1]
        if      (y_new > MAX_POS_REAL) y_new = MAX_POS_REAL;
        else if (y_new < MIN_NEG_REAL) y_new = MIN_NEG_REAL;
        gld_y  = y_new;
        gld_w1 = w1_new;
        gld_w2 = w2_new;
    endtask

    // ----------------------------------------------------------------
    // Set coefficients
    // ----------------------------------------------------------------
    task automatic set_coeffs(real rb0, real rb1, real rb2, real ra1, real ra2);
        b0 = to_fx_c(rb0); gb0 = rb0;
        b1 = to_fx_c(rb1); gb1 = rb1;
        b2 = to_fx_c(rb2); gb2 = rb2;
        a1 = to_fx_c(ra1); ga1 = ra1;
        a2 = to_fx_c(ra2); ga2 = ra2;
    endtask

    // ----------------------------------------------------------------
    // Apply one sample and compare RTL vs golden
    // ----------------------------------------------------------------
    task automatic apply_and_check(string label, real x_real, int cycle);
        real got, exp, err;
        x = to_fx_x(x_real);
        golden_tick(x_real);
        @(posedge clk); #1;
        got = to_real_x(y);
        exp = gld_y;
        err = got - exp; if (err < 0) err = -err;
        if (err <= TOLERANCE) begin
            pass_count++;
            $display("PASS [%-20s] cyc=%0d  x=%8.4f  y=%10.6f  exp=%10.6f",
                label, cycle, x_real, got, exp);
        end else begin
            fail_count++;
            $display("FAIL [%-20s] cyc=%0d  x=%8.4f  y=%10.6f  exp=%10.6f  err=%e  <<<",
                label, cycle, x_real, got, exp, err);
        end
    endtask

    // ----------------------------------------------------------------
    // Reset
    // ----------------------------------------------------------------
    task automatic do_reset();
        rst_n = 0; x = '0;
        @(posedge clk); #1;
        @(posedge clk); #1;
        rst_n = 1;
        golden_reset();
        @(posedge clk); #1;
    endtask

    // ----------------------------------------------------------------
    // LPF coefficients — Butterworth fc=1kHz fs=48kHz
    //   a1 passed as NEGATIVE, a2 passed as POSITIVE
    // ----------------------------------------------------------------
    localparam real LPF_B0 =  0.003621;
    localparam real LPF_B1 =  0.007242;
    localparam real LPF_B2 =  0.003621;
    localparam real LPF_A1 = -1.867453;   // negative
    localparam real LPF_A2 =  0.881736;   // positive

    localparam real AP_B0 = 1.0;
    localparam real AP_B1 = 0.0;
    localparam real AP_B2 = 0.0;
    localparam real AP_A1 = 0.0;
    localparam real AP_A2 = 0.0;

    real got,exp,err;
    real xv, yv;
    // ================================================================
    // TESTS
    // ================================================================
    initial begin
        $display("=== Biquad IIR Testbench ===");
        $display("    x/y format   : Q%0d.%0d (%0d-bit)", IIP-1, IFP, NX);
        $display("    coeff format : Q%0d.%0d (%0d-bit)", CIP-1, CFP, NC);
        $display("    TOLERANCE    : %e (%0d LSBs)", TOLERANCE, 2);
        $display("");

        // ------------------------------------------------------------
        // TEST 1: Reset — output must be zero while rst_n=0
        // ------------------------------------------------------------
        $display("--- Test 1: Reset ---");
        set_coeffs(LPF_B0, LPF_B1, LPF_B2, LPF_A1, LPF_A2);
        rst_n = 0; x = to_fx_x(1.0);
        @(posedge clk); #1;
        if (y === '0) begin
            pass_count++;
            $display("PASS [reset_output_zero ] y=0 during reset");
        end else begin
            fail_count++;
            $display("FAIL [reset_output_zero ] y=%0d during reset  <<<", signed'(y));
        end
        rst_n = 1;
        golden_reset();

        // ------------------------------------------------------------
        // TEST 2: All-pass (b0=1, rest=0)
        // Output must equal input delayed by exactly 1 cycle
        // ------------------------------------------------------------
        $display("");
        $display("--- Test 2: All-pass (b0=1, rest=0) ---");
        set_coeffs(AP_B0, AP_B1, AP_B2, AP_A1, AP_A2);
        do_reset();
        apply_and_check("allpass x=0.5",    0.5,   1);
        apply_and_check("allpass x=-0.25", -0.25,  2);
        apply_and_check("allpass x=0.0",    0.0,   3);
        apply_and_check("allpass x=1.0",    1.0,   4);

        // ------------------------------------------------------------
        // TEST 3: LPF Impulse response — 20 cycles
        // RTL and golden must agree within TOLERANCE each cycle
        // ------------------------------------------------------------
        $display("");
        $display("--- Test 3: LPF Impulse Response ---");
        set_coeffs(LPF_B0, LPF_B1, LPF_B2, LPF_A1, LPF_A2);
        do_reset();
        apply_and_check("impulse n=0", 1.0, 0);
        for (int n = 1; n <= 19; n++)
            apply_and_check($sformatf("impulse n=%0d", n), 0.0, n);

        // ------------------------------------------------------------
        // TEST 4: LPF Step response — 30 cycles
        // ------------------------------------------------------------
        $display("");
        $display("--- Test 4: LPF Step Response ---");
        set_coeffs(LPF_B0, LPF_B1, LPF_B2, LPF_A1, LPF_A2);
        do_reset();
        for (int n = 0; n < 30; n++)
            apply_and_check($sformatf("step n=%0d", n), 1.0, n);

        // ------------------------------------------------------------
        // TEST 5: DC Steady State
        // Compare RTL vs golden after 500 cycles — both settle to the
        // same value (which includes coefficient quantization error).
        // Checking RTL==golden, not RTL==1.0 exactly.
        // ------------------------------------------------------------
        $display("");
        $display("--- Test 5: DC Steady State (RTL vs golden) ---");
        set_coeffs(LPF_B0, LPF_B1, LPF_B2, LPF_A1, LPF_A2);
        do_reset();
        for (int n = 0; n < 500; n++) begin
            x = to_fx_x(1.0);
            golden_tick(1.0);
            @(posedge clk); #1;
        end
        begin
            got = to_real_x(y);
            exp = gld_y;
            err = got - exp; if (err < 0) err = -err;
            $display("    RTL settled  = %f", got);
            $display("    Golden settled = %f", exp);
            if (err <= TOLERANCE) begin
                pass_count++;
                $display("PASS [DC_steady_state   ] err=%e (<= %e)", err, TOLERANCE);
            end else begin
                fail_count++;
                $display("FAIL [DC_steady_state   ] err=%e (> %e)  <<<", err, TOLERANCE);
            end
        end

        // ------------------------------------------------------------
        // TEST 6: HF Attenuation — 12kHz through 1kHz LPF
        // Peak amplitude after transient must be < 0.05
        // ------------------------------------------------------------
        $display("");
        $display("--- Test 6: HF Attenuation (12kHz, cutoff 1kHz) ---");
        set_coeffs(LPF_B0, LPF_B1, LPF_B2, LPF_A1, LPF_A2);
        do_reset();
        for (int n = 0; n < 50; n++) begin   // flush transient
            xv = $sin(2.0 * 3.14159265 * 12000.0 * n / 48000.0) * 0.5;
            x = to_fx_x(xv); golden_tick(xv);
            @(posedge clk); #1;
        end
        begin
            automatic real max_amp = 0.0;
            for (int n = 50; n < 150; n++) begin
                xv = $sin(2.0 * 3.14159265 * 12000.0 * n / 48000.0) * 0.5;
                x  = to_fx_x(xv); golden_tick(xv);
                @(posedge clk); #1;
                yv = to_real_x(y); if (yv < 0) yv = -yv;
                if (yv > max_amp) max_amp = yv;
            end
            if (max_amp < 0.05) begin
                pass_count++;
                $display("PASS [HF_attenuation    ] peak=%f (< 0.05)", max_amp);
            end else begin
                fail_count++;
                $display("FAIL [HF_attenuation    ] peak=%f (should be < 0.05)  <<<", max_amp);
            end
        end

        // ------------------------------------------------------------
        // TEST 7: Saturation
        // All-pass with MAX/MIN input — output must clamp, not wrap
        // ------------------------------------------------------------
        $display("");
        $display("--- Test 7: Saturation ---");
        set_coeffs(AP_B0, AP_B1, AP_B2, AP_A1, AP_A2);
        do_reset();
        x = {1'b0, {(NX-1){1'b1}}};   // max positive
        golden_tick(to_real_x(x));
        @(posedge clk); #1;
        begin
            automatic logic signed [NX-1:0] max_pos = {1'b0, {(NX-1){1'b1}}};
            if (y === max_pos) begin
                pass_count++;
                $display("PASS [sat_max_pos       ] y=MAX_POS as expected");
            end else begin
                fail_count++;
                $display("FAIL [sat_max_pos       ] y=%0d, expected MAX_POS  <<<", signed'(y));
            end
        end
        x = {1'b1, {(NX-1){1'b0}}};   // most negative
        golden_tick(to_real_x(x));
        @(posedge clk); #1;
        begin
            automatic logic signed [NX-1:0] min_neg = {1'b1, {(NX-1){1'b0}}};
            if (y === min_neg) begin
                pass_count++;
                $display("PASS [sat_min_neg       ] y=MIN_NEG as expected");
            end else begin
                fail_count++;
                $display("FAIL [sat_min_neg       ] y=%0d, expected MIN_NEG  <<<", signed'(y));
            end
        end

        // ------------------------------------------------------------
        // TEST 8: Mid-run reset — internal state must clear
        // ------------------------------------------------------------
        $display("");
        $display("--- Test 8: Mid-run Reset ---");
        set_coeffs(LPF_B0, LPF_B1, LPF_B2, LPF_A1, LPF_A2);
        for (int n = 0; n < 10; n++) begin
            x = to_fx_x(1.0); @(posedge clk); #1;
        end
        rst_n = 0; @(posedge clk); #1;
        if (y === '0) begin
            pass_count++;
            $display("PASS [mid_run_reset     ] y=0 after reset");
        end else begin
            fail_count++;
            $display("FAIL [mid_run_reset     ] y=%0d after reset  <<<", signed'(y));
        end
        rst_n = 1; golden_reset();
        x = '0; @(posedge clk); #1;
        if (y === '0) begin
            pass_count++;
            $display("PASS [post_reset_zero   ] y=0 after reset+zero input");
        end else begin
            fail_count++;
            $display("FAIL [post_reset_zero   ] y=%0d  <<<", signed'(y));
        end

        // ------------------------------------------------------------
        // Summary
        // ------------------------------------------------------------
        $display("");
        $display("=== RESULTS: PASS=%0d  FAIL=%0d  TOTAL=%0d ===",
            pass_count, fail_count, pass_count+fail_count);
        $finish;
    end

endmodule