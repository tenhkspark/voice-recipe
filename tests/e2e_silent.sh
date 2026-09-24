#!/bin/sh
# 通し試験（無音）。席は test、記録の印は t。afplay / say は実行しない。
# 部品がまだ無い行は SKIP（失敗にしない）。
#   1. Claude Code の Stop 口（voice-reply.sh）が、CC の transcript のときだけ
#      voice.py reply を席 test で呼ぶ
#   2. reply → 要約 → 合成まで進み、再生はスタブが受ける
#   3. 音声入力の文字 → aizuchi 即答（偽ソケット）で、鳴る意図だけ再生関数へ届く
set -u
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
FIX="$HERE/fixtures"
# 実装の場所と席は外から渡す。未設定のファイルは各ケースが SKIP する。
REPLY=${VOICE_REPLY:-}
VOICEPY=${VOICE_PY:-}
VOICEIN=${VOICE_IN:-}
RESPOND=${AIZUCHI_RESPOND:-}
# 既定の席 test は印 t の契約。別の名前にすると印の検査はしない。
SEAT=${VOICE_E2E_SEAT:-test}
OTHER=${VOICE_TEST_OTHER_SEAT:-other-seat}
CWD=${VOICE_TEST_CWD:-/tmp/voice-proj}
export VOICE_E2E_SEAT="$SEAT"
OUT=$(mktemp "${TMPDIR:-/tmp}/e2e-silent.XXXXXX")

note() { printf '%s\n' "$1" | tee -a "$OUT"; }

note "e2e_silent  seat=$SEAT  mark=t  playback=stub（音は鳴らさない）"
note "case	expect	called	detail	result"

STUB=$(mktemp -d "${TMPDIR:-/tmp}/e2e-tmux.XXXXXX")
trap 'rm -rf "$STUB"; rm -f "$OUT"' EXIT
cat > "$STUB/tmux" << 'EOF'
#!/bin/sh
printf '%s\n' "$VOICE_E2E_SEAT"
EOF
chmod +x "$STUB/tmux"

gate() {
  name=$1
  expect=$2
  input=$3
  if [ ! -f "$REPLY" ]; then
    note "$name	$expect	-	voice-reply.sh が無い	SKIP"
    return
  fi
  if ! command -v jq >/dev/null 2>&1; then
    note "$name	$expect	-	jq が無い	SKIP"
    return
  fi
  # ヒアドキュメントは関数内のコマンド置換で本文が空になることがあるので、ファイル経由。
  payload=$STUB/hook.json
  printf '%s\n' "$input" > "$payload"
  # -x の追跡は stderr。stdout は捨て、stderr だけを残す。
  trace=$(CLAUDE_VOICE_MUTE=1 PATH="$STUB:$PATH" TMUX_PANE=e2e \
    sh -x "$REPLY" < "$payload" 2>&1 >/dev/null
  )
  if printf '%s\n' "$trace" | grep -F -q "voice.py reply --seat $SEAT"; then
    got=yes
  else
    got=no
  fi
  if [ "$got" = "$expect" ]; then
    res=PASS
    detail="Stop口 reply呼び出し（MUTE・再生なし）"
  else
    res=FAIL
    detail=$(printf '%s' "$trace" | tail -3 | tr '\n' ' ' | cut -c1-180)
  fi
  note "$name	$expect	$got	$detail	$res"
}

hook_json() {
  printf '{"hook_event_name":"Stop","transcript_path":"%s","cwd":"%s"}' "$1" "$CWD"
}

if [ -f "$FIX/cc-stop.jsonl" ]; then
  gate stop-cc yes "$(hook_json "$FIX/cc-stop.jsonl")"
else
  note "stop-cc	yes	-	fixtures/cc-stop.jsonl が無い	SKIP"
fi

if [ -f "$FIX/grok-updates.jsonl" ]; then
  gate stop-grok no "$(hook_json "$FIX/grok-updates.jsonl")"
else
  note "stop-grok	no	-	fixtures/grok-updates.jsonl が無い	SKIP"
fi

gate stop-missing no "$(hook_json "$FIX/no-such-transcript.jsonl")"

gate stop-not-json no 'this is not json'

# reply → 要約 → 合成、再生スタブ。aizuchi は偽ソケット。
export E2E_FIX="$FIX" E2E_VOICEPY="$VOICEPY" E2E_VOICEIN="$VOICEIN" E2E_RESPOND="$RESPOND"
export E2E_SEAT="$SEAT" E2E_CWD="$CWD" E2E_OTHER="$OTHER"
PYOUT=$(mktemp "${TMPDIR:-/tmp}/e2e-py.XXXXXX")
python3 - > "$PYOUT" << 'PY'
import io, json, os, signal, socket, socketserver, sys, tempfile, threading, importlib.util

FIX = os.environ["E2E_FIX"]
VOICEPY = os.environ["E2E_VOICEPY"]
VOICEIN = os.environ["E2E_VOICEIN"]
RESPOND = os.environ["E2E_RESPOND"]
SEAT = os.environ.get("E2E_SEAT", "test")
CWD = os.environ.get("E2E_CWD", "/tmp/voice-proj")
OTHER = os.environ.get("E2E_OTHER", "other-seat")

rows = []

def add(case, expect, called, detail, result):
    rows.append((case, expect, called, detail, result))
    print(f"{case}\t{expect}\t{called}\t{detail}\t{result}", flush=True)

if not os.path.isfile(VOICEPY):
    add("chain", "yes", "-", "voice.py が無い", "SKIP")
    add("aizuchi", "yes", "-", "voice.py が無いので続きも見ない", "SKIP")
    sys.exit(0)

# 再生バイナリは絶対パスで呼ばれる。Popen を差し替え、実体は起動しない。
import subprocess
_real_popen = subprocess.Popen
PLAY = []
SAY_SPAWN = []

class Dummy:
    def __init__(self):
        self.pid = 0
        self.returncode = 0
    def wait(self, timeout=None):
        return 0
    def poll(self):
        return 0
    def send_signal(self, sig):
        pass
    def kill(self):
        pass
    def communicate(self, *a, **k):
        return (b"", b"")

def _argv(args):
    if isinstance(args, (list, tuple)):
        return [str(x) for x in args]
    return [str(args)]

def popen(args, *a, **k):
    argv = _argv(args)
    base = os.path.basename(argv[0]) if argv else ""
    if base in ("afplay", "say") or argv[0] in ("/usr/bin/afplay", "/usr/bin/say"):
        PLAY.append(argv)
        return Dummy()
    if any(x.endswith("voice.py") for x in argv) and "say" in argv:
        SAY_SPAWN.append(argv)
        signal.alarm(0)
        text, purpose, no_play = "", "done", False
        if "say" in argv:
            i = argv.index("say")
            if i + 1 < len(argv) and not argv[i + 1].startswith("--"):
                text = argv[i + 1]
        if "--purpose" in argv:
            purpose = argv[argv.index("--purpose") + 1]
        no_play = "--no-play" in argv
        voice.speak(text, purpose=purpose, force_truncate=True, no_play=no_play)
        return Dummy()
    if any(x.endswith("respond.py") for x in argv):
        SAY_SPAWN.append(argv)  # 起動した事実だけ。実プロセスは立てない
        return Dummy()
    return _real_popen(args, *a, **k)

subprocess.Popen = popen

spec = importlib.util.spec_from_file_location("voice_e2e", VOICEPY)
voice = importlib.util.module_from_spec(spec)
spec.loader.exec_module(voice)

tmp = tempfile.mkdtemp(prefix="e2e-voice-")
cfg_path = os.path.join(tmp, "config.json")
with open(cfg_path, "w", encoding="utf-8") as f:
    json.dump({
        "enabled": True,
        "mode": "summary",
        "say_rate": 220,
        "speaker_id": 1,
        "synth_timeout": 4,
        "purposes": {"done": True, "attention": True, "error": True, "read": True},
        "quiet_hours": ["04:00", "04:01"],
        "min_interval_sec": 0,
        "post_rec_grace_sec": 0,
        "rewrite": False,
        "dedupe_window_sec": 0,
        "night_brief_hours": ["04:00", "04:01"],
        "night_brief_cap": 30,
        "pack": {"enabled": False},
        "summarizer": "off",
        "seat": SEAT,
    }, f)
for name in ("CFG", "READING", "PIDFILE", "LOCKFILE", "STOPFILE",
             "LASTTEXT", "LASTTIME", "LASTKIND", "LASTSPOKEN", "LASTSUM",
             "HOOKRAW", "SUMLOG_DIR", "QLOCKFILE", "QCOUNTFILE", "QLATEST"):
    if hasattr(voice, name):
        base = os.path.basename(getattr(voice, name))
        setattr(voice, name, os.path.join(tmp, base))
voice.CFG = cfg_path
voice.dictating = lambda: False

SYNTH = []
_real_synth = voice.aivis_synthesize
def synth_wrap(*a, **k):
    SYNTH.append(a[0] if a else "")
    return _real_synth(*a, **k)
voice.aivis_synthesize = synth_wrap

def reset():
    PLAY.clear()
    SAY_SPAWN.clear()
    SYNTH.clear()

def mark_of_log():
    path = os.path.join(voice.SUMLOG_DIR, __import__("time").strftime("%Y-%m") + ".tsv")
    try:
        lines = [ln for ln in open(path, encoding="utf-8") if ln.strip()]
    except OSError:
        return "", ""
    if not lines:
        return "", ""
    cols = lines[-1].rstrip("\n").split("\t")
    seat = cols[2] if len(cols) > 2 else ""
    mark = cols[3] if len(cols) > 3 else ""
    kind = cols[1] if len(cols) > 1 else ""
    return f"seat={seat} mark={mark} kind={kind}", mark

class NS:
    def __init__(self, seat):
        self.seat = seat
        self.no_play = False

def run_reply(seat, payload):
    reset()
    os.environ["VOICE_REPLY_SEAT"] = seat
    sys.stdin = io.StringIO(payload)
    try:
        voice.cmd_reply(NS(seat))
    except Exception as e:
        return f"error:{type(e).__name__}"
    return ""

def hook(path):
    return json.dumps({
        "hook_event_name": "Stop",
        "transcript_path": path,
        "cwd": CWD,
    }, ensure_ascii=False)

def judge_play(case, expect_play):
    err = ""
    called = "yes" if PLAY else "no"
    detail_m, mark = mark_of_log()
    engine = "aivis" if SYNTH else ("say" if any("say" in os.path.basename(p[0]) for p in PLAY) else ("afplay" if PLAY else "none"))
    if expect_play or PLAY:
        detail = f"{engine} {detail_m} synth={len(SYNTH)} play={len(PLAY)}".strip()
    else:
        detail = "再生関数は呼ばれない"
    if err:
        add(case, "yes" if expect_play else "no", called, err, "FAIL")
        return
    ok = (called == "yes") if expect_play else (called == "no")
    if expect_play and SEAT == "test" and mark != "t":
        ok = False
        detail += " 印tでない"
    add(case, "yes" if expect_play else "no", called, detail, "PASS" if ok else "FAIL")

# 鳴る: 本物の CC transcript
if os.path.isfile(os.path.join(FIX, "cc-stop.jsonl")):
    err = run_reply(SEAT, hook(os.path.join(FIX, "cc-stop.jsonl")))
    if err:
        add("chain-cc-stop", "yes", "no", err, "FAIL")
    else:
        judge_play("chain-cc-stop", True)
else:
    add("chain-cc-stop", "yes", "-", "fixtures/cc-stop.jsonl が無い", "SKIP")

if os.path.isfile(os.path.join(FIX, "cc-multichunk.jsonl")):
    err = run_reply(SEAT, hook(os.path.join(FIX, "cc-multichunk.jsonl")))
    if err:
        add("chain-cc-multichunk", "yes", "no", err, "FAIL")
    else:
        judge_play("chain-cc-multichunk", True)
else:
    add("chain-cc-multichunk", "yes", "-", "fixtures/cc-multichunk.jsonl が無い", "SKIP")

if os.path.isfile(os.path.join(FIX, "cc-nobody.jsonl")):
    err = run_reply(SEAT, hook(os.path.join(FIX, "cc-nobody.jsonl")))
    if err:
        add("chain-cc-nobody", "yes", "no", err, "FAIL")
    else:
        judge_play("chain-cc-nobody", True)
else:
    add("chain-cc-nobody", "yes", "-", "fixtures/cc-nobody.jsonl が無い", "SKIP")

# 鳴らない: 相槌だけ、Grok 形式、席違い
ack = os.path.join(tmp, "ack.jsonl")
with open(ack, "w", encoding="utf-8") as f:
    f.write(json.dumps({"message": {"role": "user", "content": [{"type": "text", "text": "考えずにOKだけ返して"}]}}) + "\n")
    f.write(json.dumps({"message": {"role": "assistant", "content": [{"type": "text", "text": "了解"}]}}) + "\n")
err = run_reply(SEAT, hook(ack))
if err:
    add("chain-ack", "no", "no", err, "FAIL")
else:
    judge_play("chain-ack", False)

if os.path.isfile(os.path.join(FIX, "grok-updates.jsonl")):
    err = run_reply(SEAT, hook(os.path.join(FIX, "grok-updates.jsonl")))
    if err:
        add("chain-grok", "no", "no", err, "FAIL")
    else:
        judge_play("chain-grok", False)
else:
    add("chain-grok", "no", "-", "fixtures/grok-updates.jsonl が無い", "SKIP")

err = run_reply(OTHER, hook(os.path.join(FIX, "cc-stop.jsonl")) if os.path.isfile(os.path.join(FIX, "cc-stop.jsonl")) else hook(ack))
if err:
    add("chain-wrong-seat", "no", "no", err, "FAIL")
else:
    kind = ""
    try:
        kind = open(voice.LASTKIND, encoding="utf-8").read().strip()
    except OSError:
        kind = ""
    called = "yes" if PLAY else "no"
    ok = called == "no" and kind == "seat-skip"
    add("chain-wrong-seat", "no", called, f"last.kind={kind or '-'}", "PASS" if ok else "FAIL")

# --- aizuchi: 偽ソケット。voicein が挨拶・感謝だけ speak する。無い部品は SKIP ---
if not os.path.isfile(VOICEIN):
    add("aizuchi-thanks", "yes", "-", "voicein.py が無い", "SKIP")
    add("aizuchi-none", "no", "-", "voicein.py が無い", "SKIP")
    add("aizuchi-intent-mute", "no", "-", "voicein.py が無い", "SKIP")
    add("aizuchi-sock-down", "no", "-", "voicein.py が無い", "SKIP")
else:
    sock_path = os.path.join(tmp, "aizuchi.sock")
    replies = {}

    class H(socketserver.StreamRequestHandler):
        def handle(self):
            for line in self.rfile:
                text = line.decode("utf-8", "replace").rstrip("\r\n")
                if not text:
                    continue
                obj = replies.get(text) or {"intent": "none", "score": 0, "id": "", "reply": ""}
                self.wfile.write((json.dumps(obj, ensure_ascii=False) + "\n").encode())
                self.wfile.flush()

    class S(socketserver.ThreadingUnixStreamServer):
        daemon_threads = True
        allow_reuse_address = True

    srv = S(sock_path, H)
    threading.Thread(target=srv.serve_forever, daemon=True).start()

    # play_aizuchi は import voice する。試験用モジュールを渡し、利用者の設定は触らない。
    sys.modules["voice"] = voice
    os.environ["VOICE_REPLY_SEAT"] = SEAT
    os.environ["AIZUCHI_SOCK"] = sock_path
    vspec = importlib.util.spec_from_file_location("voicein_e2e", VOICEIN)
    voicein = importlib.util.module_from_spec(vspec)
    vspec.loader.exec_module(voicein)
    voicein.AIZUCHI_SOCK = sock_path

    def classify(text, obj, case, expect_play):
        reset()
        replies.clear()
        replies[" ".join(text.split())] = obj
        try:
            voicein.aizuchi_reply(text)
        except Exception as e:
            add(case, "yes" if expect_play else "no", "no", f"error:{type(e).__name__}:{e}", "FAIL")
            return
        called = "yes" if PLAY else "no"
        detail = f"play={len(PLAY)} synth={len(SYNTH)}"
        ok = (called == "yes") if expect_play else (called == "no")
        if expect_play:
            _, mark = mark_of_log()
            if SEAT == "test" and mark != "t":
                ok = False
                detail += " 印tでない"
        add(case, "yes" if expect_play else "no", called, detail, "PASS" if ok else "FAIL")

    classify("ありがとう",
             {"intent": "thanks", "score": 0.99, "id": "", "reply": "どういたしまして", "lang": "ja"},
             "aizuchi-thanks", True)
    classify("天気を教えて",
             {"intent": "none", "score": 0.2, "id": "", "reply": "", "lang": "ja"},
             "aizuchi-none", False)
    classify("デプロイして",
             {"intent": "deploy", "score": 0.9, "id": "", "reply": "了解しました", "lang": "ja"},
             "aizuchi-intent-mute", False)

    reset()
    voicein.AIZUCHI_SOCK = os.path.join(tmp, "missing.sock")
    voicein.aizuchi_reply("ありがとう")
    called = "yes" if PLAY else "no"
    add("aizuchi-sock-down", "no", called, "ソケット無し", "PASS" if called == "no" else "FAIL")
    srv.shutdown()

fail = sum(1 for r in rows if r[-1] == "FAIL")
skip = sum(1 for r in rows if r[-1] == "SKIP")
passed = sum(1 for r in rows if r[-1] == "PASS")
print(f"summary\tpass={passed} fail={fail} skip={skip}", flush=True)
sys.exit(1 if fail else 0)
PY
py_status=$?
cat "$PYOUT" | tee -a "$OUT"
rm -f "$PYOUT"

fail_n=$(grep -c '	FAIL$' "$OUT" || true)
if [ "$py_status" -ne 0 ] || [ "$fail_n" -ne 0 ]; then
  note "summary-shell	-	-	python_exit=$py_status fail_lines=$fail_n	FAIL"
  exit 1
fi
note "summary-shell	-	-	python_exit=$py_status fail_lines=$fail_n	PASS"
exit 0
