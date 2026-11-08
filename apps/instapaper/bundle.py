"""Bundle Instapaper into index.lua: src/main.lua with the shared AI modules (tools/gamekit/ai.lua,
aiui.lua), through tools/gamekit/bundle_reader.py.

  python apps/instapaper/bundle.py
"""
import os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(HERE)), 'tools', 'gamekit'))
import bundle_reader  # noqa: E402

if __name__ == '__main__':
    bundle_reader.bundle(HERE)
