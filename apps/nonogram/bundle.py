"""Bundle Nonograms into index.lua (tools/gamekit/gamekit.lua + src/bank.lua + src/main.lua).

  python apps/nonogram/bundle.py
"""
import os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(HERE)), 'tools', 'gamekit'))
import bundle  # noqa: E402

if __name__ == '__main__':
    bundle.bundle(HERE)
