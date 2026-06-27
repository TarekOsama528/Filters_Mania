`timescale 1ns/1ps
// Testbench for booth_radix4_mult — Mixed Fixed-Point
// All comparisons done in integer domain (no rounding needed — exact).

module tb_booth_radix4;

    // ----------------------------------------------------------------
    // Format parameters — must match DUT
    // ----------------------------------------------------------------
    localparam int MI = 4;              // M integer bits (incl. sign)
    localparam int MF = 4;              // M fractional bits
    localparam int YI = 2;              // Y integer bits (incl. sign)
    localparam int YF = 6;              // Y fractional bits

    localparam int NM = MI + MF;        // M total width = 8
    localparam int NY = YI + YF;        // Y total width = 8
    localparam int NP = NM + NY;        // P total width = 16

    // ----------------------------------------------------------------
    // DUT ports
    // ----------------------------------------------------------------
    logic signed [NM-1:0] M;
    logic signed [NY-1:0] Y;
    logic signed [NP-1:0] P;
    logic signed [NP-1:0] expected;

    int pass_count = 0, fail_count = 0;

    booth_radix4_mult #(
        .MI(MI), .MF(MF),
        .YI(YI), .YF(YF)
    ) dut (
        .M(M), .Y(Y), .P(P)
    );

    // ----------------------------------------------------------------
    // Helper: display fixed-point value as decimal string
    //   val_int  : raw integer bits
    //   frac_bits: number of fractional bits
    // ----------------------------------------------------------------
    function automatic real to_real(logic signed [NP-1:0] val, int frac_bits);
        return real'(val) / real'(1 << frac_bits);
    endfunction

    // ----------------------------------------------------------------
    // Check task
    //   Compares integer-domain product P vs M*Y
    //   Also prints human-readable fixed-point values
    // ----------------------------------------------------------------
    task automatic check(
        string              label,
        logic signed [NM-1:0] m_in,
        logic signed [NY-1:0] y_in
    );
        M = m_in; Y = y_in; #1;

        // Golden reference: integer multiply (exact, no rounding)
        expected = NP'(signed'(m_in)) * NP'(signed'(y_in));

        if (P === expected) begin
            pass_count++;
            $display("PASS [%-16s]  M=%7.4f (%4d)  Y=%8.6f (%4d)  P=%12.8f (%6d)",
                label,
                to_real(NP'(signed'(m_in)), MF), signed'(m_in),
                to_real(NP'(signed'(y_in)), YF), signed'(y_in),
                to_real(P, MF+YF),               signed'(P));
        end else begin
            fail_count++;
            $display("FAIL [%-16s]  M=%7.4f  Y=%8.6f  P=%12.8f (got %0d, exp %0d)  <<< MISMATCH",
                label,
                to_real(NP'(signed'(m_in)), MF),
                to_real(NP'(signed'(y_in)), YF),
                to_real(P, MF+YF),
                signed'(P), signed'(expected));
        end
    endtask

    // ----------------------------------------------------------------
    // Stimulus
    // ----------------------------------------------------------------
    initial begin
        $display("=== Booth Radix-4 Multiplier — Mixed Fixed-Point ===");
        $display("    M format : Q%0d.%0d  (%0d-bit)", MI-1, MF, NM);
        $display("    Y format : Q%0d.%0d  (%0d-bit)", YI-1, YF, NY);
        $display("    P format : Q%0d.%0d  (%0d-bit)", MI+YI-1, MF+YF, NP);
        $display("");

        // ---- Directed edge cases ----

        // Zero
        check("zero*zero",     {NM{1'b0}},   {NY{1'b0}});

        // Pure integer values (fractional bits = 0)
        // M=3.0 in Q3.4 → 3 << 4 = 48
        // Y=1.0 in Q1.6 → 1 << 6 = 64
        check("3.0 * 1.0",     NM'(3  << MF), NY'(1  << YF));
        check("3.0 * -1.0",    NM'(3  << MF), NY'(-1 << YF));
        check("-3.0 * 1.0",    NM'(-3 << MF), NY'(1  << YF));
        check("-3.0 * -1.0",   NM'(-3 << MF), NY'(-1 << YF));

        // Max positive values
        // M max Q3.4 = 0111_1111 = 127 → 7.9375
        // Y max Q1.6 = 01_111111 = 127 → 1.984375
        check("Mmax * Ymax",   NM'(127),        NY'(127));
        check("Mmin * Ymin",   NM'(-128),       NY'(-128));
        check("Mmin * Ymax",   NM'(-128),       NY'(127));
        check("Mmax * Ymin",   NM'(127),        NY'(-128));

        // Fractional-only values
        // M=0.5  in Q3.4 → 0000_1000 = 8
        // Y=0.5  in Q1.6 → 00_100000 = 32
        // P=0.25 in Q4.10→ expected = 8*32 = 256
        check("0.5 * 0.5",     NM'(1  << (MF-1)), NY'(1  << (YF-1)));
        check("0.5 * -0.5",    NM'(1  << (MF-1)), NY'(-(1 << (YF-1))));

        // M=0.0625 (LSB of M) * Y=1.0
        check("LSB_M * 1.0",   NM'(1),            NY'(1  << YF));

        // M=1.0 * Y LSB
        check("1.0 * LSB_Y",   NM'(1  << MF),     NY'(1));

        // Both LSBs
        check("LSB_M * LSB_Y", NM'(1),            NY'(1));

        // Run-of-ones patterns (stress Booth encoding)
        check("run1s_M * 1.0", NM'(8'sb0111_1110),  NY'(1  << YF));
        check("alt_bits",      NM'(8'sb0101_0101),  NY'(8'sb01_010101));

        // ---- Random vectors ----
        $display("");
        $display("--- Random vectors ---");
        for (int t = 0; t < 200; t++) begin
            logic signed [NM-1:0] rm;
            logic signed [NY-1:0] ry;
            rm = $random;
            ry = $random;
            check($sformatf("rand_%0d", t), rm, ry);
        end

        $display("");
        $display("=== RESULTS: PASS=%0d  FAIL=%0d  TOTAL=%0d ===",
            pass_count, fail_count, pass_count + fail_count);
        $finish;
    end

endmodule