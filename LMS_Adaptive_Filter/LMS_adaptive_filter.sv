
// LMS Adaptive Filter — Sign-LMS approximation (sign of error only)
// Fixed-point format: Q(INTEGER_BITS-1).FRACTIONAL_BITS
//
// FSM states:
//   IDLE      — wait, hold outputs
//   SHIFT     — push x into delay line
//   COMPUTE   — calculate y = sum(w[i]*x[i]), e = d - y
//   UPDATE_W  — update weights using sign(e)
//
// Sign-LMS weight update:
//   w[i] += 2*mu * sign(e) * x[i]
//   sign(e) taken from MSB of e (1=negative, 0=positive)
//
// Why sign-LMS:
//   Avoids multiplying e*x (costly), replaces with +/- of mu*x only.
//   Trades convergence speed for hardware simplicity.
// =============================================================================

module lms_adaptive_filter #(
    parameter int N               = 4,    // filter order (taps)
    parameter int FRACTIONAL_BITS = 8,
    parameter int INTEGER_BITS    = 4
)(
    input  logic clk,
    input  logic rst_n,
    input  logic signed [INTEGER_BITS+FRACTIONAL_BITS-1:0] x,   // input sample
    input  logic signed [INTEGER_BITS+FRACTIONAL_BITS-1:0] d,   // desired signal
    input  logic signed [INTEGER_BITS+FRACTIONAL_BITS-1:0] mu,  // step size
    output logic signed [INTEGER_BITS+FRACTIONAL_BITS-1:0] y,   // filter output
    output logic signed [INTEGER_BITS+FRACTIONAL_BITS-1:0] e,   // error signal
    output logic                                            valid // output valid flag
);

    localparam int NB  = INTEGER_BITS + FRACTIONAL_BITS;

    typedef enum logic [1:0] {
        IDLE,
        SHIFT,
        COMPUTE,
        UPDATE_W
    } state_t;

    state_t state, next_state;

    logic signed [NB-1:0]  w        [N];   // adaptive weights (internal state)
    logic signed [NB-1:0]  x_buf    [N];   // input delay line

    logic signed [2*NB-1:0] y_acc;          // accumulator for FIR sum
    logic signed [NB-1:0]  y_reg;          // rescaled output
    logic signed [NB-1:0]  e_reg;          // error = d - y

    // FSM — state register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= IDLE;
        else        state <= next_state;
    end

    // FSM — next state logic
    always_comb begin
        case (state)
            IDLE:     next_state = SHIFT;
            SHIFT:    next_state = COMPUTE;
            COMPUTE:  next_state = UPDATE_W;
            UPDATE_W: next_state = IDLE;
            default:  next_state = IDLE;
        endcase
    end

    // SHIFT state — combinational output accumulator
    // Computed combinationally so COMPUTE state can register the result
    // in one clock edge without needing an extra cycle.
    always_comb begin
        y_acc = '0;
        for (int i = 0; i < N; i++)
            y_acc = y_acc + (w[i] * x_buf[i]);
    end

    // Datapath — sequential
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            y     <= '0;
            e     <= '0;
            e_reg <= '0;
            y_reg <= '0;
            valid <= 1'b0;
            for (int i = 0; i < N; i++) begin
                w    [i] <= '0;
                x_buf[i] <= '0;
            end

        end else begin
            valid <= 1'b0;   // default — deassert each cycle

            case (state)

                // ------------------------------------------------------
                // SHIFT: push new x into delay line
                // x_buf[0] = x(n), x_buf[1] = x(n-1), ...
                // ------------------------------------------------------
                SHIFT: begin
                    for (int i = N-1; i > 0; i--)
                        x_buf[i] <= x_buf[i-1];
                    x_buf[0] <= x;
                end

                // ------------------------------------------------------
                // COMPUTE: register y and e
                // y_acc is already updated combinationally from current
                // w[] and x_buf[] — safe to register here.
                // e = d - y  (desired minus filter output)
                // ------------------------------------------------------
                COMPUTE: begin
                    y_reg <= NB'(y_acc >>> FRACTIONAL_BITS);
                    e_reg <= d - NB'(y_acc >>> FRACTIONAL_BITS);
                end

                // ------------------------------------------------------
                // UPDATE_W: sign-LMS weight update
                //
                //   sign(e) = e[NB-1]  (MSB = sign bit)
                //   e > 0 (MSB=0): w[i] += 2*mu*x_buf[i] >> FRAC
                //   e < 0 (MSB=1): w[i] -= 2*mu*x_buf[i] >> FRAC
                //
                // Note: 2*mu*x_buf[i] is a full 2*NB-bit product.
                // Shift right by FRACTIONAL_BITS to rescale back to NB.
                // ------------------------------------------------------
                UPDATE_W: begin
                    for (int i = 0; i < N; i++) begin
                        if (e_reg[NB-1])
                            // error negative → subtract
                            w[i] <= w[i] - NB'((2 * mu * x_buf[i]) >>> FRACTIONAL_BITS);
                        else
                            // error positive → add
                            w[i] <= w[i] + NB'((2 * mu * x_buf[i]) >>> FRACTIONAL_BITS);
                    end
                    // Drive outputs and assert valid
                    y     <= y_reg;
                    e     <= e_reg;
                    valid <= 1'b1;
                end

                default: begin /* IDLE — hold all values */ end

            endcase
        end
    end

endmodule