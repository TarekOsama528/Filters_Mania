module booth_radix4_mult #(
    parameter int N = 8                     
)(
    input  logic signed [N-1:0]   M,        // multiplicand
    input  logic signed [N-1:0]   Y,        // multiplier
    output logic signed [2*N-1:0] P         // product (2N bits)
);

    localparam int GROUPS = (N+1)/2;        // ceil(N/2) groups
    localparam int EXTW   = 2*GROUPS+1;     // extended Y width (extra LSB 0 + sign-extended MSB)

    logic [EXTW-1:0] y_ext;
    logic signed [2*N-1:0] m_ext;
    logic signed [2*N-1:0] pp [GROUPS];

    assign m_ext = {{N{M[N-1]}}, M};        // sign-extend multiplicand to 2N bits

    // Build extended multiplier: bit0 = appended 0 (y(-1)), bits 1..N = Y, rest = sign-extended
    integer k;
    always_comb begin
        y_ext[0] = 1'b0;
        for (k = 0; k < EXTW-1; k++) begin
            if (k < N)
                y_ext[k+1] = Y[k];
            else
                y_ext[k+1] = Y[N-1];        // sign extension
        end
    end

    genvar i;
    generate
        for (i = 0; i < GROUPS; i++) begin : booth_groups
            logic [2:0] grp;
            assign grp = {y_ext[2*i+2], y_ext[2*i+1], y_ext[2*i]}; // {y(2i+1), y(2i), y(2i-1)}

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

    integer j;
    always_comb begin
        P = '0;
        for (j = 0; j < GROUPS; j++)
            P = P + (pp[j] <<< (2*j));
    end

endmodule