# Known-good EBAZ4205 reference routes

For Vivado 2020.2, use a known board preset rather than guessing DDR timing.

Recommended reference:
- DavidJRichards/EBAZ4205_BoardSupport
  - provides a Vivado 2020.2 board definition
  - its `preset.xml` is intended to configure PS memory/devices
  - use "Apply Board Preset" when running PS7 block automation

Additional 2020.2 reference:
- Halolo/ebaz4205-vivado
  - public Vivado 2020.2 demo
  - includes PS configuration matching attached DDR/NAND/etc.

Do not copy an unknown preset blindly. Compare DDR part/timing and board revision first.
