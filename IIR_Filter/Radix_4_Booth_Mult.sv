// Radix-4 Booth Multiplier — Mixed Fixed-Point
module booth_radix4_mult #(
    parameter int MI = 4,               // M integer bits  (incl. sign)
    parameter int MF = 4,               // M fractional bits
    parameter int YI = 2,               // Y integer bits  (incl. sign)
    parameter int YF = 6                // Y fractional bits
)(
    input  logic signed [MI+MF-1:0]         M,   // Q(MI-1).MF
    input  logic signed [YI+YF-1:0]         Y,   // Q(YI-1).YF
    output logic signed [MI+MF+YI+YF-1:0]   P    // Q(MI+YI-1).(MF+YF)
);

    localparam int NM     = MI + MF;            // total width of M
    localparam int NY     = YI + YF;            // total width of Y
    localparam int NP     = NM + NY;            // total width of P
    localparam int GROUPS = (NY + 1) / 2;       // ceil(NY/2) Booth groups
    localparam int EXTW   = 2 * GROUPS + 1;     // extended Y width

    // Sign-extend M to full product width (NP bits)
    logic signed [NP-1:0] m_ext;
    assign m_ext = {{NY{M[NM-1]}}, M};

    // Build extended Y: prepend y(-1)=0 at LSB, sign-extend MSB
    logic [EXTW-1:0] y_ext;
    integer k;
    always_comb begin
        y_ext[0] = 1'b0;
        for (k = 0; k < EXTW-1; k++) begin
            if (k < NY)
                y_ext[k+1] = Y[k];
            else
                y_ext[k+1] = Y[NY-1];          // sign extension
        end
    end

    // Partial products array
    logic signed [NP-1:0] pp [GROUPS];

    genvar i;
    generate
        for (i = 0; i < GROUPS; i++) begin : booth_groups
            logic [2:0] grp;
            assign grp = {y_ext[2*i+2], y_ext[2*i+1], y_ext[2*i]};

            always @(*) begin
                unique case (grp)
                    3'b000, 3'b111: pp[i] = '0;
                    3'b001, 3'b010: pp[i] =  m_ext;
                    3'b011:         pp[i] =  (m_ext <<< 1);
                    3'b100:         pp[i] = -(m_ext <<< 1);
                    3'b101, 3'b110: pp[i] = -m_ext;
                    default:        pp[i] = '0;
                endcase
            end
        end
    endgenerate

    // Sum all shifted partial products
    integer j;
    always_comb begin
        P = '0;
        for (j = 0; j < GROUPS; j++)
            P = P + (pp[j] <<< (2*j));
    end

endmodule