module CSD_Encoder #(parameter WIDTH=8) (
    input logic signed [WIDTH-1:0] b,
    input logic p,
    output logic [WIDTH-1:0] x_m,
    output logic [WIDTH-1:0] x_s
);

    for (genvar i=0; i<WIDTH; i++) begin
        assign x_m[i] = (i==0)? ~((1'b0 ~^ b[i]) || p): ~((b[i-1] ~^ b[i]) || p);
        assign x_s[i] = b[i] & x_m[i];
    end

endmodule