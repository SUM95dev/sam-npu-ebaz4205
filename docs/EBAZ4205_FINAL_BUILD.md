# EBAZ4205 final integration flow (Vivado 2020.2)

This package uses a project-local EBAZ4205 board repository. It does **not** guess DDR/MIO settings.

## 1. Fetch board support

```bash
./scripts/fetch_ebaz4205_board_support.sh
```

If the machine has no GitHub access, download/clone `DavidJRichards/EBAZ4205_BoardSupport` elsewhere and run:

```bash
./scripts/fetch_ebaz4205_board_support.sh /path/to/EBAZ4205_BoardSupport
```

## 2. Structural BD only

```bash
/home/sum/Xilinx/Vivado/2020.2/bin/vivado -mode batch -source scripts/build_ebaz4205_system.tcl | tee ebaz_bd.log
```

Expected: board part detected, PS7 preset applied, deterministic NPU/DMA control addresses.

## 3. Full synthesis

```bash
RUN_SYNTH=1 /home/sum/Xilinx/Vivado/2020.2/bin/vivado -mode batch -source scripts/build_ebaz4205_system.tcl | tee ebaz_synth.log
```

## 4. Implementation + bitstream + XSA

```bash
RUN_IMPL=1 /home/sum/Xilinx/Vivado/2020.2/bin/vivado -mode batch -source scripts/build_ebaz4205_system.tcl | tee ebaz_impl.log
```

Or run steps 1, 3 and 4 in one command:

```bash
./scripts/build_ebaz4205_final.sh
```

### Fixed control map

- NPU AXI-Lite: `0x43C00000`, range `64K`
- AXI DMA AXI-Lite: `0x40400000`, range `64K`
- DMA memory ports are automatically mapped through PS7 `S_AXI_HP0` to DDR.

The build refuses `RUN_IMPL=1` unless a board part is found and its PS7 preset was actually applied.

## Release-hardening additions

The final package includes `scripts/validate_release.sh` for a local static release check and
`scripts/summarize_ebaz_reports.sh` to condense synthesis/implementation utilization and timing.
The behavioral verification script no longer issues a second `run all` after `launch_simulation`;
individual testbenches terminate themselves and the XSim runtime is capped at 1000 ns.
An AXI-Lite sequencing test (`tb_axi_lite_read_write`) specifically checks independent AW/W arrival,
stale-read-address prevention, and read-data stability under RREADY backpressure.

### Vivado 2020.2 board-file fallback

The build first tries the fetched board files through `board.repoPaths`. On the
user's Vivado 2020.2 installation this was not enumerated in one direct Tcl
test, while copying the same board definition into Vivado's standard
`data/boards/board_files` directory was detected correctly. If the build says
`no EBAZ4205 BOARD_PART found`, run:

```bash
./scripts/install_ebaz4205_board_support_vivado.sh
```

Then verify that Vivado prints `aliexpress:ebaz4205:part0:1.1` before running the
canonical build again.
