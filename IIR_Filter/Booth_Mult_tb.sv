`timescale 1ns/1ps

module tb_booth_radix4;
    localparam int N = 8;
    logic signed [N-1:0]   M, Y;
    logic signed [2*N-1:0] P;
    logic signed [2*N-1:0] expected;
    int pass_count = 0, fail_count = 0;

    booth_radix4_mult #(.N(N)) dut (.M(M), .Y(Y), .P(P));

    task automatic check(string label, logic signed [N-1:0] m_in, logic signed [N-1:0] y_in);
        M = m_in; Y = y_in; #1;
        expected = m_in * y_in;          // golden reference: native multiply
        if (P === expected) begin
            pass_count++;
            $display("PASS [%-12s] M=%0d Y=%0d -> P=%0d (expected %0d)", label, m_in, y_in, P, expected);
        end else begin
            fail_count++;
            $display("FAIL [%-12s] M=%0d Y=%0d -> P=%0d (expected %0d)  <<< MISMATCH", label, m_in, y_in, P, expected);
        end
    endtask

    initial begin
        // Directed edge cases: zero, sign combos, ±MAX/±MIN, run-of-ones, alternating bits
        check("zero*zero",   8'sd0,    8'sd0);
        check("pos*pos",     8'sd6,    8'sd3);
        check("pos*neg",     8'sd6,   -8'sd3);
        check("neg*pos",    -8'sd6,    8'sd3);
        check("neg*neg",    -8'sd6,   -8'sd3);
        check("max*max",     8'sd127,  8'sd127);
        check("min*min",    -8'sd128, -8'sd128);
        check("min*max",    -8'sd128,  8'sd127);
        check("one*any",     8'sd1,   -8'sd45);
        check("any*one",    -8'sd45,   8'sd1);
        check("any*neg_one",-8'sd45,  -8'sd1);
        check("run_of_ones", 8'sb0111_1110, 8'sd5);
        check("alt_bits",    8'sb0101_0101, 8'sb1010_1010);

        // 200 random vectors
        for (int t = 0; t < 200; t++) begin
            logic signed [N-1:0] rm, ry;
            rm = $random; ry = $random;
            check($sformatf("rand_%0d", t), rm, ry);
        end

        $display("PASS=%0d FAIL=%0d TOTAL=%0d", pass_count, fail_count, pass_count+fail_count);
        $finish;
    end
endmodule