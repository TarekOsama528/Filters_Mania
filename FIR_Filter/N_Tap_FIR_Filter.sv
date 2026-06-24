module N_tap_FIR_Filter #(
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

    localparam WIDTH = FRACTIONAL_PART + INTEGER_PART;
    localparam logic signed [WIDTH-1:0] MAX_VAL = {1'b0, {(WIDTH-1){1'b1}}};
    localparam logic signed [WIDTH-1:0] MIN_VAL = {1'b1, {(WIDTH-1){1'b0}}};

    // Accumulator for the output
    logic signed [2*(FRACTIONAL_PART+INTEGER_PART)-1:0] acc;
    logic signed [2*(FRACTIONAL_PART+INTEGER_PART)-1:0] products [N];


        for (genvar i=0; i<N; i++) begin
            assign products[i] = data_in[i] * h_coeffs[i];
        end

    adder_tree #(
        .FRACTIONAL_PART(2*FRACTIONAL_PART),
        .INTEGER_PART(2*INTEGER_PART),
        .COUNT(N)
    ) adder_inst (
        .a(products),
        .sum(acc)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_out <= 0;
        end else begin
            if ((acc>>>FRACTIONAL_PART) > MAX_VAL) 
                data_out <= MAX_VAL;
            else if ((acc>>>FRACTIONAL_PART) < MIN_VAL)
                data_out <= MIN_VAL;
            else 
                data_out <= acc >>> FRACTIONAL_PART;
        end
    end
endmodule