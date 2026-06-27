module biquad_iir #(
    parameter INPUT_FRACTIONAL_PART =16,
    parameter INPUT_INTEGER_PART =16,
    parameter COEFF_FRACTIONAL_PART = 16,
    parameter COEFF_INTEGER_PART =16
 ) (
    input logic clk,
    input logic rst_n,
    input logic signed [INPUT_FRACTIONAL_PART+INPUT_INTEGER_PART-1:0] x,
    input logic signed [COEFF_FRACTIONAL_PART+COEFF_INTEGER_PART-1:0] b0,
    input logic signed [COEFF_FRACTIONAL_PART+COEFF_INTEGER_PART-1:0] b1,
    input logic signed [COEFF_FRACTIONAL_PART+COEFF_INTEGER_PART-1:0] b2,
    input logic signed [COEFF_FRACTIONAL_PART+COEFF_INTEGER_PART-1:0] a1,
    input logic signed [COEFF_FRACTIONAL_PART+COEFF_INTEGER_PART-1:0] a2,
    output logic signed [INPUT_FRACTIONAL_PART+INPUT_INTEGER_PART-1:0] y
 );
   localparam int IN_SIZE = INPUT_FRACTIONAL_PART+INPUT_INTEGER_PART;
   localparam int COEFF_SIZE = COEFF_FRACTIONAL_PART+COEFF_INTEGER_PART;

   logic signed [IN_SIZE+COEFF_SIZE-1:0] x_b0, x_b2, x_b1, y_a2, y_a1, b2_a2, b1_a1;
   logic signed [IN_SIZE-1:0] result_scaled;

   booth_radix4_mult #(
    .MI(INPUT_INTEGER_PART),     
    .MF(INPUT_FRACTIONAL_PART),               
    .YI(COEFF_INTEGER_PART),           
    .YF(COEFF_FRACTIONAL_PART)) 
    x_b0_mult ( .M(x),.Y(b0),.P(x_b0));

    booth_radix4_mult #(
    .MI(INPUT_INTEGER_PART),     
    .MF(INPUT_FRACTIONAL_PART),               
    .YI(COEFF_INTEGER_PART),           
    .YF(COEFF_FRACTIONAL_PART)) 
    x_b1_mult ( .M(x),.Y(b1),.P(x_b1));

    booth_radix4_mult #(
    .MI(INPUT_INTEGER_PART),     
    .MF(INPUT_FRACTIONAL_PART),               
    .YI(COEFF_INTEGER_PART),             
    .YF(COEFF_FRACTIONAL_PART)) 
    x_b2_mult ( .M(x),.Y(b2),.P(x_b2));

    booth_radix4_mult #(
    .MI(INPUT_INTEGER_PART),     
    .MF(INPUT_FRACTIONAL_PART),               
    .YI(COEFF_INTEGER_PART),           
    .YF(COEFF_FRACTIONAL_PART)) 
    y_a1_mult ( .M(y),.Y(a1),.P(y_a1));

    booth_radix4_mult #(
    .MI(INPUT_INTEGER_PART),     
    .MF(INPUT_FRACTIONAL_PART),               
    .YI(COEFF_INTEGER_PART),           
    .YF(COEFF_FRACTIONAL_PART)) 
    y_a2_mult ( .M(y),.Y(a2),.P(y_a2));

    rescale #(
    .MI(INPUT_INTEGER_PART),     
    .MF(INPUT_FRACTIONAL_PART),               
    .YI(COEFF_INTEGER_PART),            
    .YF(COEFF_FRACTIONAL_PART))
    SCALED_OUTPUT (.P(x_b0 + b1_a1),.P_scaled(result_scaled));

    assign b2_a2 = x_b2 - y_a2;

   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
         y <= 'b0;
         b1_a1 <= 'b0;
      end else begin
         b1_a1 <= x_b1 - y_a1 + b2_a2;
         y <= result_scaled;
      end
   end

endmodule