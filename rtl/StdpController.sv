/*
 * SHIP OF THESEUS - STDP CONTROLLER
 *
 * Spike-Timing-Dependent Plasticity for one synapse.
 * Tracks pre/post spike timing and computes reward-modulated weight updates.
 *
 * KEY FIXES from StdpOutline.sv:
 *   1. Timer counts step_en ticks (not clock cycles) — biologically meaningful window
 *   2. weight_out is actually computed with exponential-decay approximation
 *   3. Reward modulation: weight delta scaled by dopamine (reward_scalar)
 *
 * Q8.8 Arithmetic throughout. Weights clamped to [W_MIN=0, W_MAX=2.0].
 *
 * TIMING: The learn_en input must pulse ONCE after all N_STEPS integration
 * cycles complete (falling edge of neuron_step). The controller samples
 * pre_spike/post_spike on learn_en and runs its FSM. Weight writes happen
 * in UPDATE_LTP/UPDATE_LTD states — guaranteed before the next UART packet.
 */

module StdpController (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        step_en,         // Integration clock — timer counts these
    input  logic        learn_en,        // Pulse once per packet (sample spikes here)
    input  logic        pre_spike,       // Stimulus channel had activity
    input  logic        post_spike,      // This neuron fired
    input  logic [15:0] reward_scalar,   // Dopamine (Q8.8) from UART 0xDD
    input  logic [15:0] weight_in,       // Current weight from WeightRam (Q8.8)
    output logic [15:0] weight_out,      // Updated weight (Q8.8, clamped)
    output logic        weight_we        // Write-enable pulse (1 cycle)
);

    // --- STDP parameters (matching Rust stdp.rs) ---
    localparam logic [15:0] A_PLUS  = 16'h0003; // ~0.01 in Q8.8 (0.01 * 256 ≈ 2.56 → 3)
    localparam logic [15:0] A_MINUS = 16'h0003; // ~0.012 in Q8.8 (0.012 * 256 ≈ 3.07 → 3)
    localparam logic [15:0] W_MIN   = 16'h0000; // 0.0
    localparam logic [15:0] W_MAX   = 16'h0200; // 2.0 in Q8.8

    // --- State Machine ---
    typedef enum logic [2:0] {
        IDLE,
        TRACK_PRE,   // Pre-spike occurred, waiting for Post
        TRACK_POST,  // Post-spike occurred, waiting for Pre
        UPDATE_LTP,  // Pre → Post: Potentiate (increase weight)
        UPDATE_LTD   // Post → Pre: Depress (decrease weight)
    } stdp_state_t;

    stdp_state_t state, next_state;
    logic [7:0]  timer;           // Delta-t counter (step ticks)
    logic        pre_sampled;     // Latched pre_spike at learn_en
    logic        post_sampled;    // Latched post_spike at learn_en

    // --- Decay Factor Approximation ---
    // exp(-dt/tau) ≈ 1.0 >> (timer >> 3)
    // Halves every 8 step ticks. At tau≈20 steps, this is a reasonable piecewise fit.
    // timer=0 → 0x0100 (1.0), timer=8 → 0x0080 (0.5), timer=16 → 0x0040 (0.25), etc.
    logic [15:0] decay_factor;
    logic [3:0]  shift_amount;

    assign shift_amount = (timer[7:3] > 4'd8) ? 4'd8 : timer[7:3]; // Cap at 8 shifts (≈0.004)
    assign decay_factor = 16'h0100 >> shift_amount;

    // --- Weight Delta Computation (combinational) ---
    logic [31:0] dw_raw;       // A * decay_factor (Q16.16)
    (* use_dsp = "yes" *)
    logic [31:0] dw_modulated; // dw_stage1 * reward_scalar (Q16.16)
    logic [15:0] dw_stage1;   // dw_raw[23:8] — Q8.8 intermediate
    logic [15:0] dw_final;     // Truncated to Q8.8
    logic [15:0] weight_sum;   // weight_in + dw_final (for LTP)
    logic [15:0] weight_diff;  // weight_in - dw_final (for LTD)
    logic        ltp_overflow; // Detects addition overflow

    always_comb begin
        // Default: LTP computation (LTD reuses same magnitude)
        // Q8.8 × Q8.8 → Q16.16: extract Q8.8 result from bits [23:8]
        dw_raw       = A_PLUS * decay_factor;              // Q8.8 × Q8.8 = Q16.16
        dw_stage1    = dw_raw[23:8];                       // Q8.8 result (= A × decay)
        dw_modulated = dw_stage1 * reward_scalar;          // Q8.8 × Q8.8 = Q16.16
        dw_final     = dw_modulated[23:8];                 // Q8.8 result (= A × decay × reward)

        // Saturating add for LTP
        weight_sum   = weight_in + dw_final;
        ltp_overflow = (weight_sum < weight_in);            // Carry overflow

        // Saturating subtract for LTD
        weight_diff  = (weight_in > dw_final) ? (weight_in - dw_final) : 16'h0000;
    end

    // --- State Register + Timer (step-gated) ---
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= IDLE;
            timer        <= 8'h00;
            pre_sampled  <= 1'b0;
            post_sampled <= 1'b0;
        end else begin
            state <= next_state;

            // Latch spike flags on learn_en pulse (once per UART packet)
            if (learn_en) begin
                pre_sampled  <= pre_spike;
                post_sampled <= post_spike;
            end

            // Timer counts step_en ticks, NOT clock cycles
            if (state == TRACK_PRE || state == TRACK_POST) begin
                if (step_en)
                    timer <= timer + 8'd1;
            end else begin
                timer <= 8'h00;
            end
        end
    end

    // --- Next-State Logic (combinational) ---
    always_comb begin
        next_state = state;
        case (state)
            IDLE: begin
                // Transition on learn_en sample
                if (learn_en) begin
                    if (pre_spike)       next_state = TRACK_PRE;
                    else if (post_spike) next_state = TRACK_POST;
                end
            end

            TRACK_PRE: begin
                // LTP: Post arrived after Pre
                if (learn_en && post_spike) next_state = UPDATE_LTP;
                else if (timer == 8'hFF)    next_state = IDLE; // Timeout
            end

            TRACK_POST: begin
                // LTD: Pre arrived after Post
                if (learn_en && pre_spike) next_state = UPDATE_LTD;
                else if (timer == 8'hFF)   next_state = IDLE; // Timeout
            end

            UPDATE_LTP, UPDATE_LTD: next_state = IDLE;
        endcase
    end

    // --- Output Logic ---
    always_comb begin
        weight_out = weight_in;
        weight_we  = 1'b0;

        case (state)
            UPDATE_LTP: begin
                weight_we = 1'b1;
                // Potentiate: increase weight, clamp at W_MAX
                if (ltp_overflow || weight_sum > W_MAX)
                    weight_out = W_MAX;
                else
                    weight_out = weight_sum;
            end

            UPDATE_LTD: begin
                weight_we = 1'b1;
                // Depress: decrease weight, floor at W_MIN
                weight_out = weight_diff; // Already floors at 0 via sat_sub
            end

            default: begin
                weight_out = weight_in;
                weight_we  = 1'b0;
            end
        endcase
    end

endmodule
