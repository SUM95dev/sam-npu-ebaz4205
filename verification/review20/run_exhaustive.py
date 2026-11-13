#!/usr/bin/env python3
"""Extra long-running HDL regression, outside the finite 200us XSim suite."""
import os, pathlib, subprocess, tempfile
root=pathlib.Path(__file__).resolve().parents[2]
flags=['-B',os.environ['IVERILOG_BASE']] if os.environ.get('IVERILOG_BASE') else []
with tempfile.TemporaryDirectory() as t:
    exe=str(pathlib.Path(t)/'add.vvp')
    subprocess.run([os.environ.get('IVERILOG','iverilog'),*flags,'-g2005','-s','tb_add_exhaustive','-o',exe,
                    *map(str,sorted((root/'rtl').glob('*.v'))),str(root/'verification/review20/tb_add_exhaustive.v')],check=True)
    run=subprocess.run([os.environ.get('VVP','vvp'),exe],capture_output=True,text=True,timeout=30,check=True)
    print(run.stdout,end='')
    if 'PASS exhaustive Add: 131072' not in run.stdout or 'FAIL' in run.stdout:
        raise SystemExit(1)
