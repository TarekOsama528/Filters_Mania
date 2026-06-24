`timescale 1ns/1ps

module tb_csd_fir;

    localparam N               = 8;
    localparam INTEGER_PART    = 1;
    localparam FRACTIONAL_PART = 15;
    localparam WIDTH           = INTEGER_PART + FRACTIONAL_PART; // 16
    localparam real SCALE      = 2.0**FRACTIONAL_PART;
    localparam real Q_MAX      = (2.0**(WIDTH-1) - 1.0) / SCALE;  //  0.999969...
    localparam real Q_MIN      = -(2.0**(WIDTH-1)) / SCALE;       // -1.0
    // Tolerance must cover two distinct error sources:
    //  1) final output rounding  : 1 LSB
    //  2) stimulus quantization  : to_fixed() truncates each real sample/coeff
    //     to FRACTIONAL_PART bits before it ever reaches the DUT, so the
    //     "exact real" golden reference and the "exact real value the DUT
    //     actually received" already differ slightly. This error appears in
    //     each of the N product terms, so it can accumulate up to ~N LSBs
    //     in the worst case. This is expected quantization behavior, not a
    //     DUT bug -- a real DUT bug would show errors far larger than this.
    localparam real TOL        = (N + 2.0) / SCALE;

    logic clk;
    logic rst_n;
    logic signed [WIDTH-1:0] h_coeffs [0:N-1];
    logic signed [WIDTH-1:0] data_in  [0:N-1];
    logic signed [WIDTH-1:0] data_out;

    // shared stimulus/golden storage (avoids passing unpacked arrays through
    // task/function args, which iverilog does not support)
    real samples [0:N-1];
    real coeffs  [0:N-1];

    int errors;
    int tests;
    real max_abs_err;

    CSD_FIR_Filter #(
        .N(N),
        .FRACTIONAL_PART(FRACTIONAL_PART),
        .INTEGER_PART(INTEGER_PART)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .h_coeffs(h_coeffs),
        .data_in(data_in),
        .data_out(data_out)
    );

    // clock
    always #5 clk = ~clk;

    // ---- fixed-point <-> real helpers ----
    function real to_real(logic signed [WIDTH-1:0] v);
        return real'(v) / SCALE;
    endfunction

    function logic signed [WIDTH-1:0] to_fixed(real v);
        real scaled;
        longint rounded;
        scaled = v * SCALE;
        rounded = longint'(scaled); // truncate towards zero is fine for stimulus generation
        return WIDTH'(rounded);
    endfunction

    function real saturate_real(real v);
        if (v > Q_MAX) return Q_MAX;
        else if (v < Q_MIN) return Q_MIN;
        else return v;
    endfunction

    // golden reference computed entirely in floating point, reads module-level
    // samples[]/coeffs[] arrays directly
    function real golden_ref();
        real acc;
        acc = 0.0;
        for (int k = 0; k < N; k++)
            acc += samples[k] * coeffs[k];
        return saturate_real(acc);
    endfunction

    // drive the current contents of samples[]/coeffs[] and check the result
    // after the output register latency
    task automatic run_vector(string name);
        real expected, actual, err;
        for (int k = 0; k < N; k++) begin
            data_in[k]  = to_fixed(samples[k]);
            h_coeffs[k] = to_fixed(coeffs[k]);
        end
        expected = golden_ref();

        @(posedge clk);
        #1; // settle combinational adder tree before the clock captures it
        @(posedge clk); // data_out registered on this edge

        actual = to_real(data_out);
        err = (actual - expected);
        if (err < 0) err = -err;

        tests++;
        if (err > max_abs_err) max_abs_err = err;

        if (err > TOL) begin
            errors++;
            $display("[FAIL] %-18s expected=%.6f actual=%.6f err=%.6f (> tol %.6f)",
                      name, expected, actual, err, TOL);
        end else begin
            $display("[PASS] %-18s expected=%.6f actual=%.6f err=%.6f",
                      name, expected, actual, err);
        end
    endtask

    initial begin
        clk   = 0;
        rst_n = 0;
        errors = 0;
        tests  = 0;
        max_abs_err = 0.0;
        for (int k = 0; k < N; k++) begin
            data_in[k]  = '0;
            h_coeffs[k] = '0;
        end

        repeat (2) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // ---- Test 1: simple averaging filter, known step input ----
        for (int k = 0; k < N; k++) begin
            coeffs[k]  = 1.0 / N;     // moving average
            samples[k] = 0.25;
        end
        run_vector("moving_avg_dc");

        // ---- Test 2: impulse response check ----
        for (int k = 0; k < N; k++) begin
            coeffs[k]  = (k == 0) ? 0.5 : 0.0;
            samples[k] = (k == 0) ? 0.3 : 0.0;
        end
        run_vector("impulse");

        // ---- Test 3-22: randomized vectors within normal (non-saturating) range ----
        for (int t = 0; t < 20; t++) begin
            for (int k = 0; k < N; k++) begin
                int rnd_s, rnd_c;
                // IMPORTANT: $urandom_range() returns an UNSIGNED 32-bit value.
                // Subtracting 10000 directly from it and passing the unsigned
                // result straight into $itor() would wrap around to a huge
                // positive number whenever the range result is < 10000
                // (unsigned arithmetic, per IEEE 1800), instead of giving a
                // small negative real. Assigning into a signed `int` first
                // reinterprets the wrapped bit pattern correctly as two's
                // complement, so $itor() then converts it to the intended
                // small negative real.
                rnd_s = $urandom_range(0, 20000) - 10000; // [-10000, 10000] as signed int
                rnd_c = $urandom_range(0, 20000) - 10000;
                // keep |sample|,|coeff| small enough that the true sum has very
                // low probability of saturating, so we are testing numerical
                // accuracy rather than the saturation path
                samples[k] = $itor(rnd_s) / 100000.0; // [-0.1, 0.1]
                coeffs[k]  = $itor(rnd_c) / 100000.0; // [-0.1, 0.1]
            end
            run_vector($sformatf("random_%0d", t));
        end

        // ---- Test 23/24: deliberate saturation check (sum exceeds Q1.15 range) ----
        for (int k = 0; k < N; k++) begin
            coeffs[k]  = 0.9;
            samples[k] = 0.9; // sum of products = 8 * 0.81 = 6.48, way out of [-1, ~1)
        end
        run_vector("force_saturate_pos");

        for (int k = 0; k < N; k++) begin
            coeffs[k]  = 0.9;
            samples[k] = -0.9;
        end
        run_vector("force_saturate_neg");

        $display("--------------------------------------------------");
        $display("Tests run   : %0d", tests);
        $display("Failures    : %0d", errors);
        $display("Max abs err : %.6f (tolerance = %.6f)", max_abs_err, TOL);
        if (errors == 0)
            $display("RESULT: ALL TESTS PASSED");
        else
            $display("RESULT: %0d TEST(S) FAILED", errors);
        $display("--------------------------------------------------");

        $finish;
    end

endmodule