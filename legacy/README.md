# legacy/ — superseded, kept

These four modules were replaced on 2026-08-01 when the memory became a
modified-Harvard system ([`../Memory_System.vhd`](../Memory_System.vhd)). They
are kept, not deleted: they are the operator's original work and they are the
exact input that produced the measurements in `../DIAGNOSIS.md`.

Nothing here is in the build. Removing them from `sim/run_diag.py`,
`syn/estimate_area.py` and `syn/pharvard.tcl` is what took them out.

| File | Why it went |
|---|---|
| `Instruction_Memory.vhd` | A ROM with a **combinational** read. That simulates but does not map to FPGA block RAM, which is synchronous. It also could not be written, so code space was not memory. |
| `Data_Memory.vhd` | Its whole `set/write_read/data_out/update` walk existed to hand-roll a memory protocol. With a real dual-port RAM there is no protocol left to run. |
| `Instruction_Memory_Address_Register.vhd` | A three-state FSM with a `ready` handshake whose real job was tracking read latency. Latency belongs to the memory, so it moved inside `Memory_System` as a plain `register_n`. |
| `Data_Memory_Address_Register.vhd` | Same, on the data side. |

## What replaced them, and what did not

The address registers did **not** move across verbatim. Inside
`Memory_System` they are two `register_n` instances named `Fetch_Addr_Reg` and
`Data_Addr_Reg`, and their purpose is narrower: they record *which address the
word currently on each bus belongs to*, which the memory publishes as
`fetch_addr_q` / `data_addr_q`. A consumer compares those against what it asked
for instead of counting cycles. There is no handshake and no state machine.

One thing did stay in the CPU, and it is worth being clear that this is not the
IMAR under a new name: `internal_pc_current` holds the address of the
instruction being executed. That is an architectural value — the incrementer
needs a base that does not move mid-instruction, and `JAL` needs it to form the
return address — not a memory-interface detail.

## The defects these files carried

Recorded so the history is not lost with the code. All are documented in
`../DIAGNOSIS.md`:

- both `Data_Memory` and the address registers inferred **latches**, because
  their datapath values were driven from combinational processes
  (`ghdl --synth` rejects them; simulation never noticed);
- every one of them asserted `ready` a cycle **before** the data it advertised
  was visible;
- all four used the `update_state -> previous_state` idiom that self-locks when
  a stall lasts two consecutive cycles;
- `Data_Memory` zeroed its output whenever `read_data_enable` was low and only
  restarted on an address change, so a `STORE` followed by a `LOAD` of the same
  address returned 0.

Made with my soul - Swately <3
