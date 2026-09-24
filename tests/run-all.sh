#!/bin/sh
# 検収用の一括チェック。音は鳴らさない。
# 順: test_paths.py → e2e_silent.sh → aizuchi の smoke.tsv と
# smoke-dictation.tsv。常駐ソケットは AIZUCHI_SOCK。
# 空なら AIZUCHI_SERVE と AIZUCHI_MODEL があれば一時ソケットで起動する。
# 材料の既定は tests/aizuchi/（文字だけ）。1 つ落ちても最後まで走り、失敗があれば終了コード 1。
# voice.py 等の場所は VOICE_PY / VOICE_REPLY / VOICE_IN（tests/README.md）。
set -u
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
AIZUCHI=${AIZUCHI_DIR:-"$HERE/aizuchi"}
PY=${AIZUCHI_PYTHON:-python3}
SERVE=${AIZUCHI_SERVE:-}
MODEL=${AIZUCHI_MODEL:-}
SOCK=${AIZUCHI_SOCK:-}
SPEAK="$AIZUCHI/speak_intents.txt"

py_ok() {
  if [ -x "$PY" ]; then
    return 0
  fi
  command -v "$PY" >/dev/null 2>&1
}

started=
tmp=
cleanup() {
  if [ -n "$started" ]; then
    kill "$started" 2>/dev/null || true
    wait "$started" 2>/dev/null || true
  fi
  if [ -n "$tmp" ]; then
    rm -rf "$tmp"
  fi
}
trap cleanup EXIT INT TERM

# 常駐へ 1 往復できるか。音は出さない（respond.py / afplay は使わない）。
ping_sock() {
  SOCK_TRY=$1 "$PY" -c '
import os, socket, sys
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.settimeout(3)
try:
    s.connect(os.environ["SOCK_TRY"])
    s.sendall("テスト\n".encode())
    s.settimeout(30)
    line = s.makefile("r", encoding="utf-8").readline()
except OSError:
    sys.exit(1)
sys.exit(0 if line.startswith("{") else 1)
'
}

sock_ready=
if [ -n "$SOCK" ] && ping_sock "$SOCK"; then
  sock_ready=1
fi
if [ -z "$sock_ready" ]; then
  if ! py_ok || [ -z "$SERVE" ] || [ ! -f "$SERVE" ] || [ -z "$MODEL" ] || [ ! -f "$MODEL" ]; then
    SOCK=
  else
    tmp=$(mktemp -d "${TMPDIR:-/tmp}/runall-aizuchi.XXXXXX")
    SOCK="$tmp/aizuchi.sock"
    "$PY" "$SERVE" --model "$MODEL" --sock "$SOCK" \
      >"$tmp/serve.log" 2>&1 &
    started=$!
    i=0
    while [ "$i" -lt 40 ]; do
      if ping_sock "$SOCK"; then
        break
      fi
      if ! kill -0 "$started" 2>/dev/null; then
        break
      fi
      i=$((i + 1))
      sleep 0.5
    done
    if ! ping_sock "$SOCK"; then
      SOCK=
    fi
  fi
fi

rows=$tmp/rows
if [ -z "$tmp" ]; then
  rows=$(mktemp "${TMPDIR:-/tmp}/runall-rows.XXXXXX")
fi
: > "$rows"

# 名前、結果、内訳。結果は PASS / FAIL。
add_row() {
  printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$rows"
}

# --- 1. test_paths.py ---
log=$(mktemp "${TMPDIR:-/tmp}/runall-paths.XXXXXX")
python3 "$HERE/test_paths.py" >"$log" 2>&1
st=$?
detail=$(grep -E 'passed, .* failed' "$log" | tail -1 | tr -d '\r')
if [ -z "$detail" ]; then
  detail="exit=$st"
fi
if [ "$st" -eq 0 ]; then
  add_row "test_paths.py" PASS "$detail"
else
  add_row "test_paths.py" FAIL "$detail"
fi
fail_paths=$(mktemp "${TMPDIR:-/tmp}/runall-pathfail.XXXXXX")
grep '^FAIL ' "$log" > "$fail_paths" || true

# --- 2. e2e_silent.sh ---
log2=$(mktemp "${TMPDIR:-/tmp}/runall-e2e.XXXXXX")
CLAUDE_VOICE_MUTE=1 sh "$HERE/e2e_silent.sh" >"$log2" 2>&1
st=$?
psum=$(grep '^summary	' "$log2" | tail -1 | tr -d '\r')
if [ -n "$psum" ]; then
  detail=${psum#summary	}
else
  detail="exit=$st"
fi
if [ "$st" -eq 0 ]; then
  add_row "e2e_silent.sh" PASS "$detail"
else
  add_row "e2e_silent.sh" FAIL "$detail"
fi
fail_e2e=$(mktemp "${TMPDIR:-/tmp}/runall-e2efail.XXXXXX")
grep '	FAIL$' "$log2" > "$fail_e2e" || true

# --- 3, 4. smoke.tsv / smoke-dictation.tsv を int8 常駐で ---
log3=$(mktemp "${TMPDIR:-/tmp}/runall-smoke.XXXXXX")
if [ -z "$SOCK" ]; then
  add_row "smoke.tsv" FAIL "常駐に繋がらない（AIZUCHI_SOCK、または AIZUCHI_SERVE と AIZUCHI_MODEL）"
  add_row "smoke-dictation.tsv" FAIL "常駐に繋がらない（AIZUCHI_SOCK、または AIZUCHI_SERVE と AIZUCHI_MODEL）"
else
  SOCK_TRY=$SOCK AIZUCHI_DIR=$AIZUCHI "$PY" - >"$log3" << 'PY'
import json, os, socket, sys

sock = os.environ["SOCK_TRY"]
here = os.environ["AIZUCHI_DIR"]
speak = set()
with open(os.path.join(here, "speak_intents.txt"), encoding="utf-8") as f:
    for line in f:
        line = line.split("#", 1)[0].strip()
        if line:
            speak.add(line)

def load_tsv(path):
    rows = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            p = line.rstrip("\n").split("\t")
            if len(p) == 3 and p[0] != "lang":
                rows.append((p[1], p[2]))
    return rows

def ask(texts):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(180)
    s.connect(sock)
    rf = s.makefile("r", encoding="utf-8")
    out = []
    try:
        for text in texts:
            s.sendall(text.encode("utf-8") + b"\n")
            line = rf.readline()
            if not line:
                raise OSError("常駐が応答を閉じた")
            j = json.loads(line)
            if not isinstance(j, dict) or not isinstance(j.get("intent"), str):
                raise OSError("常駐の応答が意図でない")
            if j.get("intent") == "error":
                raise OSError(j.get("error") or "intent=error")
            out.append(j["intent"])
    finally:
        try:
            rf.close()
        except OSError:
            pass
        s.close()
    return out

def would_speak(intent):
    return intent in speak

def emit(name, ok, detail):
    print(f"{name}\t{'PASS' if ok else 'FAIL'}\t{detail}", flush=True)

# smoke.tsv: 意図正答 >= 0.9、none の誤爆 <= 0.01（onnx_eval と同じ）
smoke = load_tsv(os.path.join(here, "smoke.tsv"))
try:
    pred = ask([t for t, _ in smoke])
except OSError as e:
    emit("smoke.tsv", False, f"常駐エラー: {e}")
    emit("smoke-dictation.tsv", False, "smoke の途中で常駐が落ちた")
    sys.exit(0)
hit = pos = nfire = nn = 0
misses = []
for (text, want), got in zip(smoke, pred):
    if want == "none":
        nn += 1
        if got != "none":
            nfire += 1
            misses.append(f"smoke.tsv\t{text}\twant={want}\tgot={got}")
    else:
        pos += 1
        if got == want:
            hit += 1
        else:
            misses.append(f"smoke.tsv\t{text}\twant={want}\tgot={got}")
acc = hit / max(pos, 1)
misfire = nfire / max(nn, 1)
ok = acc >= 0.9 and misfire <= 0.01
emit("smoke.tsv", ok,
     f"intent {hit}/{pos}={acc:.4f} (need >=0.9) "
     f"none誤爆 {nfire}/{nn}={misfire:.4f} (need <=0.01)")

# smoke-dictation.tsv: 鳴らしてはいけない誤鳴 <=1%、鳴るべきの取りこぼし <=10%
# 鳴る = speak_intents.txt の意図（常駐が voice.py へ渡す側）
dic = load_tsv(os.path.join(here, "smoke-dictation.tsv"))
try:
    pred = ask([t for t, _ in dic])
except OSError as e:
    emit("smoke-dictation.tsv", False, f"常駐エラー: {e}")
    sys.exit(0)
silent = sfire = reply = rmiss = 0
for (text, want), got in zip(dic, pred):
    spoke = would_speak(got)
    if want == "silent":
        silent += 1
        if spoke:
            sfire += 1
            misses.append(f"smoke-dictation.tsv\t{text}\twant=silent\tgot={got}")
    elif want == "reply":
        reply += 1
        if not spoke:
            rmiss += 1
            misses.append(f"smoke-dictation.tsv\t{text}\twant=reply\tgot={got}")
    else:
        misses.append(f"smoke-dictation.tsv\t{text}\twant={want}\tgot={got}")
sf = sfire / max(silent, 1)
rm = rmiss / max(reply, 1)
ok = sf <= 0.01 and rm <= 0.10 and (silent + reply) == len(dic)
emit("smoke-dictation.tsv", ok,
     f"silent誤鳴 {sfire}/{silent}={sf:.4f} (need <=0.01) "
     f"reply取りこぼし {rmiss}/{reply}={rm:.4f} (need <=0.10)")
for m in misses[:12]:
    print("MISS\t" + m, flush=True)
extra = len(misses) - 12
if extra > 0:
    print(f"MISS\t...\t他 {extra} 件", flush=True)
PY
  while IFS= read -r line; do
    name=${line%%	*}
    rest=${line#*	}
    case $name in
      smoke.tsv|smoke-dictation.tsv)
        res=${rest%%	*}
        det=${rest#*	}
        add_row "$name" "$res" "$det"
        ;;
    esac
  done < "$log3"
  # 採点が行を出さなかった項目は FAIL
  if ! grep -q '^smoke.tsv	' "$rows"; then
    add_row "smoke.tsv" FAIL "採点が結果を出さなかった"
  fi
  if ! grep -q '^smoke-dictation.tsv	' "$rows"; then
    add_row "smoke-dictation.tsv" FAIL "採点が結果を出さなかった"
  fi
fi

n=$(wc -l < "$rows" | tr -d ' ')
bad=$(grep -c '	FAIL	' "$rows" || true)
good=$((n - bad))
if [ "$bad" -eq 0 ]; then
  total=PASS
else
  total=FAIL
fi

printf '%s\n' "run-all  音なし  int8常駐"
printf '%s\n' "項目	結果	内訳"
cat "$rows"
printf '%s\n' "合計	$total	${good}/${n}"

if [ -s "$fail_paths" ] || [ -s "$fail_e2e" ] || grep -q '^MISS	' "$log3" 2>/dev/null; then
  printf '%s\n' "--- 落ちた行（smoke は先頭 12 件） ---"
  if [ -s "$fail_paths" ]; then
    sed 's/^/test_paths.py	/' "$fail_paths"
  fi
  if [ -s "$fail_e2e" ]; then
    sed 's/^/e2e_silent.sh	/' "$fail_e2e"
  fi
  grep '^MISS	' "$log3" 2>/dev/null || true
fi

rm -f "$log" "$log2" "$log3" "$fail_paths" "$fail_e2e"
if [ -z "$tmp" ]; then
  rm -f "$rows"
fi

[ "$total" = PASS ]
