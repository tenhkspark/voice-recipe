#!/usr/bin/env python3
"""Check language-to-voice-key routing through voice.py's silent query mode."""
import os
import subprocess
import sys
from pathlib import Path


HERE = Path(__file__).resolve().parent
FIXTURE = HERE / "fixtures" / "lang-route.tsv"


def main():
    voice = os.environ.get("VOICE_PY")
    if not voice:
        print("FAIL\tVOICE_PY is required")
        return 2
    failures = 0
    with FIXTURE.open(encoding="utf-8") as f:
        next(f, None)
        for number, line in enumerate(f, 2):
            lang, text, expected = line.rstrip("\n").split("\t")
            try:
                result = subprocess.run(
                    [sys.executable, voice, "--select-voice-key", text],
                    check=False, capture_output=True, text=True, timeout=15,
                    env={**os.environ, "VOICE_NO_PLAY": "1"},
                )
                got = result.stdout.strip()
                ok = result.returncode == 0 and got == expected
                detail = f"{lang} want={expected} got={got or '(empty)'}"
                if result.returncode:
                    detail += f" exit={result.returncode}"
            except (OSError, subprocess.TimeoutExpired) as e:
                ok, detail = False, f"{lang} {e}"
            print(f"{'PASS' if ok else 'FAIL'}\t{detail}")
            failures += not ok
    print(f"summary\t{4 - failures}/4")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
