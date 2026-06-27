module rescale #(
    parameter int MI = 4,
    parameter int MF = 4,
    parameter int YI = 2,
    parameter int YF = 6
)(
    input  logic signed [MI+MF+YI+YF-1:0] P,
    output logic signed [MI+MF-1:0]        P_scaled
);

    localparam int NM = MI + MF;
    localparam int NP = NM + YI + YF;

    localparam signed [NM-1:0] MAX_POS =  {1'b0, {(NM-1){1'b1}}};  // +7.9375
    localparam signed [NM-1:0] MIN_NEG =  {1'b1, {(NM-1){1'b0}}};  // -8.0000

    localparam signed [NP-1:0] SAT_MAX = NP'(signed'(MAX_POS)) <<< YF;  //  8128
    localparam signed [NP-1:0] SAT_MIN = NP'(signed'(MIN_NEG)) <<< YF;  // -8192

    localparam signed [NP-1:0] ROUND_CONST = NP'(1 << (YF-1));

    logic signed [NP:0]   P_rounded_wide;
    logic signed [NP-1:0] P_rounded;

    assign P_rounded_wide = {P[NP-1], P} + ROUND_CONST;
    assign P_rounded      = P_rounded_wide[NP-1:0];

    always_comb begin
        if      (P_rounded > SAT_MAX) P_scaled = MAX_POS;
        else if (P_rounded < SAT_MIN) P_scaled = MIN_NEG;
        else                          P_scaled = P_rounded[NM+YF-1 : YF];
    end

endmodule