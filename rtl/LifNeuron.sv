/*
 * SHIP OF THESEUS - NEUROMORPHIC CORE
 * Component: LifNeuron.sv
 * Description: Leaky Integrate-and-Fire Neuron (Step-Gated, Peak Capture)
 * 
 * Arithmetic: 16-bit Fixed Point (Q8.8)
 * Formula: V(t+1) = V(t) + Stimulus - (V(t) >> DecayShift)
 *
 * KEY DESIGN: The neuron only integrates when `step_en` is HIGH.
 * This matches the Rust model where each call to `step()` = one integration.
 * Without gating, the neuron runs at 100 MHz and fires/resets millions of
 * times between UART packets, making the sampled potential always zero.
 *
 * PEAK CAPTURE: When the neuron fires, `v_peak` latches the membrane
 * potential *before* the hard reset, exactly matching the Rust `check_fire()`
 * which returns `Some(peak)` before zeroing `membrane_potential`.
 */

module LifNeuron #(
    parameter integer DECAY_SHIFT = 3,
    parameter integer NEURON_ID   = 0
)(
    input  logic        clk,
    input  logic        rst_n,
    input  logic        step_en,         // Gate: only integrate when pulsed
    input  logic [15:0] stimulus,        // Input current (Q8.8)
    input  logic [15:0] threshold_val,   // Firing threshold (Q8.8) — driven by NeuronParamRam
    output logic [15:0] v_potential,     // Live membrane potential (Q8.8)
    output logic [15:0] v_peak,          // Peak potential captured before spike reset
    output logic        spike_out        // 1 = neuron fired this step
);

    logic [15:0] v_reg;
    logic [15:0] v_next;
    logic [15:0] v_leak;
    logic        did_spike;

    // --- LEAKY: Passive Decay ---
    assign v_leak = v_reg >> DECAY_SHIFT;

    // --- INTEGRATE & FIRE: Combinational next-state ---
    always_comb begin
        did_spike = 1'b0;
        if (v_reg >= threshold_val && threshold_val != 16'h0000) begin
            // FIRE: Capture peak, then hard reset
            v_next    = 16'h0000;
            did_spike = 1'b1;
        end else begin
            // INTEGRATE: V(t+1) = V(t) + stimulus - leak
            // Saturating addition to prevent overflow wrap-around
            if ((v_reg + stimulus) < v_reg) 
                v_next = 16'hFFFF;
            else
                v_next = v_reg + stimulus - v_leak;
        end
    end

    // --- OUTPUTS ---
    assign spike_out   = did_spike;
    assign v_potential = v_reg;

    // --- STATE REGISTER (Step-Gated) ---
    // Only updates when step_en is pulsed — one integration per UART packet.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            v_reg  <= 16'h0000;
            v_peak <= 16'h0000;
        end else if (step_en) begin
            // Capture peak BEFORE the reset takes effect (matches Rust check_fire)
            if (did_spike)
                v_peak <= v_reg;  // Latch the firing voltage
            v_reg <= v_next;
        end
    end

endmodule
