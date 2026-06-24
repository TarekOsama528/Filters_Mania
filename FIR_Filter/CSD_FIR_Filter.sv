module CSD_FIR_Filter #(
    parameter N = 8, // Number of taps
    parameter FRACTIONAL_PART = 16,
    parameter INTEGER_PART = 16
)(
    input logic clk,
    input logic rst_n,
    input logic signed [FRACTIONAL_PART+INTEGER_PART-1:0] h_coeffs [0:N-1], // Filter coefficients
    input logic signed [FRACTIONAL_PART+INTEGER_PART-1:0] data_in [0:N-1], // Input data samples
    output logic signed [FRACTIONAL_PART+INTEGER_PART-1:0] data_out
);

    localparam WIDTH = INTEGER_PART + FRACTIONAL_PART;

    logic [FRACTIONAL_PART+INTEGER_PART-1:0] x_s [N];
    logic [FRACTIONAL_PART+INTEGER_PART-1:0] x_m [N];
    genvar i;
    generate
        for (i=0; i<N; i++) begin
            CSD_Encoder #(.WIDTH(INTEGER_PART+FRACTIONAL_PART)) cds_enc (.b(h_coeffs[i]),.p(1'b0),.x_m(x_m[i]),.x_s(x_s[i]));
        end
    endgenerate

    logic signed [WIDTH-1:0] acc;
    logic signed [2*(FRACTIONAL_PART+INTEGER_PART)-1:0] products [N];
    logic signed [FRACTIONAL_PART+INTEGER_PART-1:0] products_scaled [N];

    genvar j;
    generate
        for (i=0; i<N; i++) begin
            logic signed [(2*WIDTH)-1:0] data_ext;
            logic signed [(2*WIDTH)-1:0] term [WIDTH];
 
            assign data_ext = {{(WIDTH){data_in[i][WIDTH-1]}}, data_in[i]}; // sign-extend data to PRODW
 
            for (j=0; j<WIDTH; j++) begin
                // non-zero CSD digit at bit j -> add or subtract a shifted copy of data_in[i]
                assign term[j] = x_m[i][j] ? (x_s[i][j] ? -(data_ext <<< j) : (data_ext <<< j))
                                            : '0;
            end
 
            always_comb begin
                products[i] = 'b0;
                for (int t=0; t<WIDTH; t++)
                    products[i] = products[i] + term[t];
            end

            assign products_scaled[i] = products[i] >>> FRACTIONAL_PART;
        end
    endgenerate


    adder_tree #(.FRACTIONAL_PART(FRACTIONAL_PART),.INTEGER_PART(INTEGER_PART),.COUNT(N)) adder (
        .a(products_scaled),
        .sum(acc)
    );


    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_out <= 'b0;
        end
        else begin
            data_out <= acc;
        end

    end

endmodule