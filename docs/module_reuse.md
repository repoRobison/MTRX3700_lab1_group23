# Reaction Time Game module reuse

This file records how the nine supplied lesson modules are used in Piano Tiles.
It is intended to support the assignment report's module-reuse discussion. The
modules are integrated into active hardware; none is an unused compatibility
shell.

| Lesson module | Reuse and documented changes |
|---|---|
| `top_level` | Retains the DE1-SoC integration role and physical port names. Expanded to connect four lanes, three difficulties, scoring, multiplier and the custom modules. Pin assignments remain in `top_level.qsf`. |
| `seven_seg` | Retains the supplied active-low decimal truth table and blank default. Six instances moved under `display`: four lanes and two score digits. |
| `timer` | Retains the reset/up/enable/start-value interface and millisecond counter. The 50 MHz-to-1 ms prescaler is present and parameterised through `CLKS_PER_MS`; `beat_gen` uses it as an upward phase timer. |
| `debounce` | Retains the supplied interface, configurable stable-count delay and internal `synchroniser`. The sequential bookkeeping was condensed into one equivalent clocked block. |
| `synchroniser` | Retains the supplied two-consecutive-flip-flop structure and `clk`, `x`, `y` interface. |
| `rng` | Retains the lesson's ten-bit Fibonacci LFSR and taps. Reaction-game offset/range conversion was removed because Piano Tiles consumes the raw random bits; the non-zero power-up seed and simulation guards are documented in the source. |
| `reaction_time_fsm` | Substantially adapted as expected by the brief. The single reaction sequence became explicit `RESET`, `PLAYING` and `GAME_OVER` states. It now owns difficulty-change restarts, gameplay resets and the terminal LED flash. Per-note countdowns remain in the scheduler data path so four lanes can overlap. |
| `display` | Retains the lesson hierarchy of `bcd_encoder_4` feeding `seven_seg`, expanded to own all six physical HEX outputs. It blanks inactive lanes, leaves the two-digit score visible at game over and refuses to truncate values above 99. |
| `bcd_encoder_4` | The supplied marked scaffold was completed without changing its 11-bit input or four digit outputs. Four 2048-by-4 synchronous lookup ROMs implement ones, tens, hundreds and thousands. Quartus infers the arrays as ROM blocks. |

## Additional Piano Tiles modules

The nine reused modules are supported by purpose-specific modules permitted by
the assignment: `button_input`, `beat_gen`, `note_scheduler`, `lane_controller`,
`hit_detector`, `level_select`, `multiplier`, and `score`. Shared constants live
in `game_params.svh`.

`score_bcd` was removed after `bcd_encoder_4` and `display` replaced it and
passed unit, integration and Quartus synthesis checks. Keeping both converters
would have made ownership ambiguous.

## Verification mapping

- `top_level`: `system_tb.sv`
- `seven_seg`: `seven_seg_tb.sv`
- `timer`: `timer_tb.sv` and `beat_gen_tb.sv`
- `debounce`: `debounce_tb.sv` and `button_input_tb.sv`
- `synchroniser`: `synchroniser_tb.sv`
- `rng`: `rng_tb.sv`
- `reaction_time_fsm`: `reaction_time_fsm_tb.sv`
- `display`: `display_tb.sv`
- `bcd_encoder_4`: `bcd_encoder_4_tb.sv`

Every additional active RTL module also has direct self-checking coverage;
`lane_controller_tb.sv` was added to close the last unit-test gap.
