<p align="center">
  <img src="docs/logo.png" width="220" alt="Spikenaut">
</p>

<h1 align="center">spikenaut-core-sv</h1>
<p align="center">Parameterized Q8.8 spiking neuron IP cores for FPGA neuromorphic systems</p>

<p align="center">
  <img src="https://img.shields.io/badge/language-SystemVerilog-blue" alt="SystemVerilog">
  <img src="https://img.shields.io/badge/license-GPL--3.0-orange" alt="GPL-3.0">
  <img src="https://img.shields.io/badge/target-Xilinx%20%7C%20Intel%20%7C%20Lattice-green" alt="FPGA">
</p>

---

Synthesizable, parameterized SystemVerilog IP cores providing a complete spiking neuron
system: Q8.8 LIF neurons with step-gated integration, reward-modulated STDP learning,
and dual-port parameter/weight RAMs. Drop-in for any Xilinx/Altera/Lattice FPGA.

## Features

- `LifNeuron #(DECAY_SHIFT, NEURON_ID, DATA_WIDTH)` — Q8.8 LIF with saturating arithmetic and peak capture
- `StdpController #(A_PLUS, A_MINUS, W_MIN, W_MAX, TAU_SHIFT)` — reward-modulated STDP FSM
- `WeightRam #(DEPTH, DEFAULT_WEIGHT)` — dual-port Q8.8 weight RAM with `$readmemh` init
- `NeuronParamRam #(DEPTH)` — dual-port threshold/parameter RAM
- On-chip learning: STDP runs every tick without host involvement
- Loads weights exported by [spikenaut-fpga](https://github.com/rmems/spikenaut-fpga)

## Files

```
rtl/
  LifNeuron.sv          — Q8.8 LIF neuron
  StdpController.sv     — Reward-modulated STDP FSM
  WeightRam.sv          — Dual-port weight RAM
  NeuronParamRam.sv     — Threshold parameter RAM
  SegDisplay.sv         — 4-digit 7-segment display driver
tb/
  LifNeuron_tb.sv       — LIF testbench
```

## LIF Neuron Model

```
τ dV/dt = -(V - V_rest) + R·I(t)
```

Implemented as Q8.8 fixed-point discrete-time: `V[t+1] = V[t] >> DECAY_SHIFT + stimulus`.
Fires when `V ≥ threshold`; resets to `V_rest = 0` after spike.

*Lapicque (1907); Abbott (1999)*

## STDP Learning Rule

```
ΔW = A+ · exp(-Δt/τ+)   if pre before post
ΔW = A- · exp(-Δt/τ-)   if post before pre
```

Implemented via bit-shift exponential decay. Reward-modulated by dopamine scalar.

*Bi & Poo (1998); Hebb (1949)*

## Integration Example

```systemverilog
LifNeuron #(
    .DECAY_SHIFT(3),    // τ ≈ 8 ticks
    .NEURON_ID(0),
    .DATA_WIDTH(16)     // Q8.8
) neuron0 (
    .clk(clk), .rst(rst),
    .stimulus(weighted_input),
    .threshold(param_ram_out),
    .spike(spike[0]),
    .membrane(membrane[0])
);
```

## Part of the Spikenaut Ecosystem

| Library | Purpose |
|---------|---------|
| [spikenaut-bridge-sv](https://github.com/rmems/spikenaut-bridge-sv) | UART host-FPGA protocol |
| [spikenaut-soc-sv](https://github.com/rmems/spikenaut-soc-sv) | Complete reference SoC |
| [spikenaut-fpga](https://github.com/rmems/spikenaut-fpga) | Rust-side parameter export |

## License

GPL-3.0-or-later
