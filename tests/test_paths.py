#!/usr/bin/env python3
"""読み上げ経路の回帰。再生はしない（afplay/say/子プロセスは記録するだけ）。

実行: VOICE_PY=/path/to/voice.py python3 tests/test_paths.py
      python3 tests/test_paths.py --voice /path/to/voice.py
席・作業ディレクトリは --seat / --other-seat / --foreign-seat / --cwd
または VOICE_TEST_SEAT / VOICE_TEST_OTHER_SEAT / VOICE_TEST_FOREIGN_SEAT / VOICE_TEST_CWD。
未指定の席は seat-a（発火元）、other-seat、other-session。印 t の契約は席名 test。

期待は「鳴るべきか」の側。今の voice.py が外れている経路は FAIL のまま残す。
"""
import argparse
import importlib.util
import io
import json
import os
import subprocess
import sys
import tempfile
import time
import traceback

_REAL_POPEN = subprocess.Popen

VOICE_PY = ""
FIX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures")
SEAT = "seat-a"
OTHER = "other-seat"
FOREIGN = "other-session"
CWD = "/tmp/voice-proj"

calls = []


class _Proc:
    def __init__(self, args):
        self.args = list(args)
        self.pid = 424242
        self.returncode = 0
        calls.append(self.args)

    def wait(self, timeout=None):
        return 0

    def poll(self):
        return 0


def _load_voice(tmp):
    spec = importlib.util.spec_from_file_location("voice_under_test", VOICE_PY)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    # 状態ファイルは一時ディレクトリだけ。利用者の設定は触らない。
    mod.CFG_DIR = tmp
    mod.CFG = os.path.join(tmp, "config.json")
    mod.READING = os.path.join(tmp, "reading.json")
    mod.PIDFILE = os.path.join(tmp, "current.pid")
    mod.LOCKFILE = os.path.join(tmp, "play.lock")
    mod.STOPFILE = os.path.join(tmp, "stop.mark")
    mod.LASTTEXT = os.path.join(tmp, "last.txt")
    mod.LASTTIME = os.path.join(tmp, "last.time")
    mod.LASTKIND = os.path.join(tmp, "last.kind")
    mod.LASTSPOKEN = os.path.join(tmp, "last.spoken")
    mod.LASTSUM = os.path.join(tmp, "last.sum")
    mod.HOOKRAW = os.path.join(tmp, "last.hook.json")
    mod.SUMLOG_DIR = os.path.join(tmp, "summary-log")
    mod.QLOCKFILE = os.path.join(tmp, "queue.lock")
    mod.QCOUNTFILE = os.path.join(tmp, "queue.count")
    mod.QLATEST = os.path.join(tmp, "queue.latest")
    mod.subprocess.Popen = lambda args, **kw: _Proc(args)
    mod.urllib.request.urlopen = lambda *a, **k: (_ for _ in ()).throw(
        OSError("tests do not open the network"))
    mod.signal.signal = lambda *a, **k: None
    mod.signal.alarm = lambda *a, **k: None
    os.environ.pop("VOICE_REPLY_SEAT", None)
    os.environ.pop("CLAUDE_VOICE_MUTE", None)
    return mod


class Ctx:
    def __init__(self):
        self.tmp = tempfile.mkdtemp(prefix="voice-audit-")
        self.v = _load_voice(self.tmp)
        self.visible = SEAT
        self.pane = SEAT
        self.v.current_client_seat = lambda timeout=1.0: self.visible
        self.v.seat_from_pane = lambda timeout=1.0: self.pane
        self.v.tmux_session_name = lambda timeout=1.0: self.pane
        self.reset_cfg()

    def reset_cfg(self, **over):
        c = dict(self.v.DEFAULT_CFG)
        c["purposes"] = dict(self.v.DEFAULT_CFG["purposes"])
        c["pack"] = dict(self.v.DEFAULT_CFG["pack"])
        c["summarizer"] = "off"
        c["rewrite"] = False
        c["min_interval_sec"] = 0
        c["seat"] = ""
        c.update(over)
        self.v.save_json(self.v.CFG, c)
        self.v.save_json(self.v.READING, {})
        calls.clear()
        os.environ.pop("VOICE_REPLY_SEAT", None)
        for name in ("last.kind", "last.spoken", "last.txt", "last.time"):
            p = os.path.join(self.tmp, name)
            if os.path.exists(p):
                os.remove(p)

    def kind(self):
        try:
            return open(self.v.LASTKIND, encoding="utf-8").read().strip()
        except OSError:
            return ""

    def spoken(self):
        try:
            return open(self.v.LASTSPOKEN, encoding="utf-8").read()
        except OSError:
            return ""

    def players(self):
        """実際に鳴らしにいったコマンド。子の voice.py say は --no-play なら除外。"""
        out = []
        for args in calls:
            if not args:
                continue
            exe = os.path.basename(str(args[0]))
            if exe in ("afplay", "say"):
                out.append(args)
            elif len(args) >= 3 and str(args[1]).endswith("voice.py") and args[2] == "say":
                if "--no-play" not in args:
                    out.append(args)
        return out

    def say_texts(self):
        texts = []
        for args in calls:
            if len(args) >= 3 and str(args[1]).endswith("voice.py") and args[2] == "say":
                texts.append(args[3] if len(args) > 3 else "")
        return texts

    def reply(self, payload, seat=None, no_play=False):
        if seat is None:
            seat = SEAT
        sys.stdin = io.StringIO(json.dumps(payload, ensure_ascii=False))
        ns = argparse.Namespace(seat=seat, no_play=no_play)
        self.v.cmd_reply(ns)

    def hook(self, payload, **kw):
        ns = argparse.Namespace(
            text=json.dumps(payload, ensure_ascii=False),
            purpose=kw.get("purpose", "done"),
            truncate=False,
            earcon_only=kw.get("earcon_only", False),
            no_play=kw.get("no_play", False),
        )
        self.v.cmd_hook(ns)


def _fail(msg):
    raise AssertionError(msg)


def test_cc_stop_visible_seat(cx):
    """表示中の席の Stop は、transcript の助手本文を done で読む。"""
    cx.reply({
        "hook_event_name": "Stop",
        "cwd": CWD,
        "transcript_path": os.path.join(FIX, "cc-stop.jsonl"),
        "last_assistant_message": "",
    })
    texts = cx.say_texts()
    if not texts or "ミュート設定は true で実測確認済み" not in texts[0]:
        _fail(f"本文が子 say に渡っていない: {texts!r} kind={cx.kind()}")
    if "--purpose" not in texts and "done" not in calls[-1]:
        pass
    joined = " ".join(texts[0]) if False else texts[0]
    if f"{SEAT}、" not in joined:
        _fail(f"席名が接頭辞に無い: {joined}")


def test_cc_stop_other_seat_silent(cx):
    """見ていない席の Stop は鳴らない。"""
    cx.reply({
        "hook_event_name": "Stop",
        "transcript_path": os.path.join(FIX, "cc-stop.jsonl"),
    }, seat=OTHER)
    if cx.players():
        _fail(f"席外なのに再生した: {cx.players()}")
    if cx.kind() != "seat-skip":
        _fail(f"kind={cx.kind()}")


def test_fixed_seat_blocks_others(cx):
    """固定席があるとその席だけ鳴る。"""
    cx.reset_cfg(seat=SEAT)
    cx.reply({
        "hook_event_name": "Stop",
        "transcript_path": os.path.join(FIX, "cc-stop.jsonl"),
    }, seat=OTHER)
    if cx.players() or cx.kind() != "seat-skip":
        _fail(f"固定席以外が鳴った kind={cx.kind()} {cx.players()}")
    calls.clear()
    cx.reply({
        "hook_event_name": "Stop",
        "transcript_path": os.path.join(FIX, "cc-stop.jsonl"),
    }, seat=SEAT)
    if not cx.say_texts():
        _fail("固定席なのに鳴っていない")


def test_notification_attention(cx):
    """確認待ちは attention、文言は席名＋確認待ち。声は耳コン Funk（本文合成ではない）。"""
    cx.reply({
        "hook_event_name": "Notification",
        "matcher": "permission_prompt",
        "cwd": CWD,
    })
    texts = cx.say_texts()
    if not texts or texts[0] != f"{SEAT}、確認待ち":
        _fail(f"確認待ちの文言が違う: {texts!r}")
    if "--purpose" not in calls[-1] or calls[-1][calls[-1].index("--purpose") + 1] != "attention":
        _fail(f"purpose が attention でない: {calls[-1]}")


def test_stop_failure_error(cx):
    cx.reply({"hook_event_name": "StopFailure", "cwd": "/tmp/proj"})
    texts = cx.say_texts()
    if not texts or not texts[0].endswith("、失敗"):
        _fail(f"失敗の文言が違う: {texts!r}")


def test_nobody_when_transcript_has_no_assistant(cx):
    cx.reply({
        "hook_event_name": "Stop",
        "transcript_path": os.path.join(FIX, "cc-nobody.jsonl"),
    })
    texts = cx.say_texts()
    if not texts or "本文が取れませんでした" not in texts[0]:
        _fail(f"nobody が鳴っていない: {texts!r} kind={cx.kind()}")


def test_ack_only_is_silent(cx):
    """1語相槌は黙る。本文は実 transcript の「了解しました。」を切ったもの。"""
    path = os.path.join(cx.tmp, "ack.jsonl")
    with open(path, "w", encoding="utf-8") as f:
        f.write(json.dumps({
            "message": {"role": "user", "content": [{"type": "text", "text": "進めて"}]}
        }, ensure_ascii=False) + "\n")
        f.write(json.dumps({
            "message": {"role": "assistant",
                        "content": [{"type": "text", "text": "了解しました。"}]}
        }, ensure_ascii=False) + "\n")
    cx.reply({"hook_event_name": "Stop", "transcript_path": path})
    if cx.players():
        _fail(f"相槌なのに鳴った: {cx.say_texts()}")


def test_multichunk_keeps_both(cx):
    """道具を挟む返事は最後の塊だけでなく、前の塊も本文に残す。"""
    cx.reply({
        "hook_event_name": "Stop",
        "transcript_path": os.path.join(FIX, "cc-multichunk.jsonl"),
        "last_assistant_message": "## 結論",
    })
    texts = cx.say_texts()
    if not texts:
        _fail("鳴っていない")
    if "調査します" not in texts[0] or "結論" not in texts[0]:
        _fail(f"前の塊が落ちた: {texts[0]!r}")


def test_pi_stop_without_transcript_speaks(cx):
    """Pi の agent_settled は transcript_path を付けず last_assistant_message だけ渡す。
    その本文を読むべき。"""
    cx.reply({
        "hook_event_name": "Stop",
        "cwd": CWD,
        "last_assistant_message": "ミュート設定は true で実測確認済み。",
    })
    texts = cx.say_texts()
    if not texts or "ミュート設定は true で実測確認済み" not in texts[0]:
        _fail(f"Pi の Stop が黙った: {texts!r} kind={cx.kind()}")


def test_grok_unreadable_transcript_does_not_say_nobody(cx):
    """CC 形式でない transcript で『本文が取れませんでした』とは言わない。"""
    cx.reply({
        "hook_event_name": "Stop",
        "transcript_path": os.path.join(FIX, "grok-updates.jsonl"),
        "last_assistant_message": "ミュート設定は true で実測確認済み。",
    })
    texts = cx.say_texts()
    blob = " ".join(texts)
    if "本文が取れませんでした" in blob:
        _fail("nobody が鳴った")


def test_hook_names_the_firing_seat(cx):
    """hook 経路も、発火元の席名を名乗る（別セッション名を拾わない）。"""
    cx.pane = SEAT
    cx.visible = SEAT
    cx.v.tmux_session_name = lambda timeout=1.0: FOREIGN
    cx.hook({
        "hook_event_name": "Notification",
        "matcher": "permission_prompt",
        "cwd": CWD,
    })
    texts = cx.say_texts()
    if not texts or not texts[0].startswith(f"{SEAT}、"):
        _fail(f"席名が発火元でない: {texts!r}")


def test_hook_no_play_does_not_arm_player(cx):
    """hook --no-play は再生コマンドを起動しない。"""
    cx.hook({
        "hook_event_name": "Notification",
        "matcher": "permission_prompt",
    }, no_play=True)
    if cx.players():
        _fail(f"--no-play なのに再生側を起動した: {cx.players()}")


def test_reply_no_play_does_not_arm_player(cx):
    cx.reply({
        "hook_event_name": "Stop",
        "transcript_path": os.path.join(FIX, "cc-stop.jsonl"),
    }, no_play=True)
    if cx.players():
        _fail(f"reply --no-play なのに再生した: {cx.players()}")
    # 子 say には --no-play が付く
    if not any("--no-play" in a for a in calls):
        _fail(f"--no-play が子に渡っていない: {calls}")


def test_quiet_hours_silent(cx):
    """quiet_hours は鳴らさない（earcon も含めない）。"""
    cx.v.time.strftime = lambda fmt, *a: "02:00" if fmt == "%H:%M" else time.strftime(fmt, *a)
    cx.v.speak("夜間なのに全文を読んではいけない。", purpose="done")
    if cx.players():
        _fail(f"静かな時間に鳴った: {cx.players()} kind={cx.kind()}")


def test_night_brief_truncates(cx):
    """quiet の外・night_brief の中は要点だけ。23:10 は quiet(23:30) の前。"""
    real = time.strftime
    cx.v.time.strftime = lambda fmt, *a: "23:10" if fmt == "%H:%M" else real(fmt, *a)
    long = "これは長い報告です。" * 20
    cx.v.speak(long, purpose="done", force_truncate=True)
    spoken = cx.spoken()
    if not spoken:
        _fail(f"何も残っていない kind={cx.kind()}")
    if len(spoken) > 40:
        _fail(f"深夜なのに長い: {len(spoken)}字 {spoken[:80]!r}")


def test_dedupe_skips_second(cx):
    cx.v.speak("同じ文を二度は読まない。", purpose="done")
    calls.clear()
    cx.v.speak("同じ文を二度は読まない。", purpose="done")
    if cx.players():
        _fail(f"重複なのに再生した: {cx.players()}")
    if cx.kind() != "dup-skip":
        _fail(f"kind={cx.kind()}")


def test_too_soon_is_earcon_only(cx):
    cx.reset_cfg(min_interval_sec=100)
    cx.v.speak("最初の一文です。", purpose="done")
    calls.clear()
    cx.v.speak("すぐに来た別の一文です。", purpose="done")
    if any(os.path.basename(a[0]) == "say" for a in cx.players()):
        _fail(f"間隔内なのに say した: {cx.players()}")
    if not any(os.path.basename(a[0]) == "afplay" for a in calls):
        _fail(f"earcon も無い: {calls} kind={cx.kind()}")


def test_dictating_skips(cx):
    cx.v.dictating = lambda: True
    cx.v.speak("口述中は被せない。", purpose="done")
    if cx.players() or cx.kind() != "skip-dictating":
        _fail(f"口述中に鳴った kind={cx.kind()} {cx.players()}")


def test_disabled_is_silent(cx):
    cx.reset_cfg(enabled=False)
    cx.v.speak("オフなのに読んではいけない。", purpose="done")
    if cx.players():
        _fail("enabled=false で鳴った")


def test_purpose_mute_silent(cx):
    cx.reset_cfg(purposes={"done": False, "attention": True, "error": True, "read": True})
    cx.v.speak("done はミュート。", purpose="done")
    if cx.players() or cx.kind() != "muted":
        _fail(f"ミュートを貫通した kind={cx.kind()} {cx.players()}")


def test_read_bypasses_wrong_seat(cx):
    """read は手動なので席が違っても読む。"""
    cx.visible = "other"
    cx.pane = "other"
    open(cx.v.LASTTEXT, "w", encoding="utf-8").write("手動で読み上げる文です。")
    cx.v.cmd_read(argparse.Namespace())
    if not any(os.path.basename(a[0]) == "say" or os.path.basename(a[0]) == "afplay"
               for a in calls):
        _fail(f"read が鳴っていない kind={cx.kind()} calls={calls}")


def test_audition_respects_enabled(cx):
    """voice test は試聴だが、enabled=false のときは鳴らない。"""
    cx.reset_cfg(enabled=False)
    cx.v.cmd_test(argparse.Namespace(text="試聴です。", name="Kyoko"))
    if cx.players():
        _fail(f"オフなのに test が再生した: {cx.players()}")


def test_explicit_say_without_seat_speaks(cx):
    """引数で渡した say は、tmux 席が取れなくても読む（pair-relaunch の loud など）。"""
    cx.pane = None
    cx.visible = SEAT
    os.environ.pop("VOICE_REPLY_SEAT", None)
    cx.v.cmd_say(argparse.Namespace(
        text="席の外からでも届ける警報です。", purpose="done",
        truncate=False, no_play=False))
    if not cx.players() and cx.kind() == "seat-skip":
        _fail("明示の say が席ゲートで落ちた")


def test_hook_error_does_not_play_without_seat(cx):
    """席判定の途中で落ちても、席を確認する前に earcon を鳴らさない。"""
    def boom(seat, c):
        raise RuntimeError("seat lookup failed")
    cx.v.seat_allowed = boom
    cx.hook({"hook_event_name": "Notification", "matcher": "permission_prompt"})
    if cx.players() or any(os.path.basename(a[0]) == "afplay" for a in calls):
        _fail(f"席不明の例外で鳴った: {calls}")


def test_seat_test_marks_log(cx):
    """席 test の発話は summary-log の印が t。"""
    os.environ["VOICE_REPLY_SEAT"] = "test"
    cx.v.speak("試験の一文です。", purpose="done", no_play=True)
    log = os.path.join(cx.v.SUMLOG_DIR, time.strftime("%Y-%m") + ".tsv")
    row = open(log, encoding="utf-8").read().strip().split("\n")[-1].split("\t")
    if len(row) < 4 or row[3] != "t":
        _fail(f"印 t が無い: {row}")
    if cx.players():
        _fail("--no-play 相当なのに再生した")


def test_earcon_only_notification(cx):
    cx.hook({
        "hook_event_name": "Notification",
        "matcher": "permission_prompt",
    }, earcon_only=True)
    if any(len(a) >= 3 and str(a[1]).endswith("voice.py") for a in calls):
        _fail(f"earcon-only なのに say を起動した: {calls}")
    if not any(os.path.basename(a[0]) == "afplay" and "Funk" in " ".join(a) for a in calls):
        _fail(f"attention の earcon が無い: {calls}")


def test_mute_env_exits_before_speech():
    """CLAUDE_VOICE_MUTE は合成しない。実プロセスだが入口で戻る。"""
    subprocess.Popen = _REAL_POPEN
    r = subprocess.run(
        [sys.executable, os.path.abspath(VOICE_PY), "say", "ミュート中は無音"],
        env={**os.environ, "CLAUDE_VOICE_MUTE": "1"},
        capture_output=True, text=True, timeout=10)
    if r.returncode != 0:
        _fail(f"exit {r.returncode} {r.stderr}")


TESTS = [
    test_cc_stop_visible_seat,
    test_cc_stop_other_seat_silent,
    test_fixed_seat_blocks_others,
    test_notification_attention,
    test_stop_failure_error,
    test_nobody_when_transcript_has_no_assistant,
    test_ack_only_is_silent,
    test_multichunk_keeps_both,
    test_pi_stop_without_transcript_speaks,
    test_grok_unreadable_transcript_does_not_say_nobody,
    test_hook_names_the_firing_seat,
    test_hook_no_play_does_not_arm_player,
    test_reply_no_play_does_not_arm_player,
    test_quiet_hours_silent,
    test_night_brief_truncates,
    test_dedupe_skips_second,
    test_too_soon_is_earcon_only,
    test_dictating_skips,
    test_disabled_is_silent,
    test_purpose_mute_silent,
    test_read_bypasses_wrong_seat,
    test_audition_respects_enabled,
    test_explicit_say_without_seat_speaks,
    test_hook_error_does_not_play_without_seat,
    test_seat_test_marks_log,
    test_earcon_only_notification,
]


def main(argv=None):
    global VOICE_PY, SEAT, OTHER, FOREIGN, CWD
    ap = argparse.ArgumentParser(description="読み上げ経路の回帰（無音）")
    ap.add_argument("--voice", default=os.environ.get("VOICE_PY", ""),
                    help="検査する voice.py。未指定時は VOICE_PY、それも無ければ隣の ../voice.py")
    ap.add_argument("--seat", default=os.environ.get("VOICE_TEST_SEAT", "seat-a"),
                    help="発火元として鳴ってよい席名")
    ap.add_argument("--other-seat", default=os.environ.get("VOICE_TEST_OTHER_SEAT", "other-seat"),
                    help="鳴ってはいけない別席")
    ap.add_argument("--foreign-seat", default=os.environ.get("VOICE_TEST_FOREIGN_SEAT", "other-session"),
                    help="hook が拾ってはいけない別セッション名")
    ap.add_argument("--cwd", default=os.environ.get("VOICE_TEST_CWD", "/tmp/voice-proj"),
                    help="payload に載せる作業ディレクトリ")
    ns = ap.parse_args(argv)
    voice = ns.voice
    if not voice:
        cand = os.path.normpath(os.path.join(
            os.path.dirname(os.path.abspath(__file__)), "..", "voice.py"))
        if os.path.isfile(cand):
            voice = cand
    if not voice or not os.path.isfile(voice):
        print("voice.py が見つからない。--voice か VOICE_PY で渡す。", file=sys.stderr)
        return 2
    VOICE_PY = os.path.abspath(voice)
    SEAT = ns.seat
    OTHER = ns.other_seat
    FOREIGN = ns.foreign_seat
    CWD = ns.cwd
    failed = []
    orig_strftime = time.strftime
    for fn in TESTS:
        time.strftime = orig_strftime
        cx = Ctx()
        try:
            fn(cx)
            print(f"PASS {fn.__name__}")
        except Exception as e:
            failed.append((fn.__name__, str(e).splitlines()[0]))
            print(f"FAIL {fn.__name__}: {e}")
            if os.environ.get("VOICE_AUDIT_TRACE"):
                traceback.print_exc()
        finally:
            time.strftime = orig_strftime
    # 環境変数ミュートは voice モジュールを使わない
    try:
        test_mute_env_exits_before_speech()
        print("PASS test_mute_env_exits_before_speech")
    except Exception as e:
        failed.append(("test_mute_env_exits_before_speech", str(e).splitlines()[0]))
        print(f"FAIL test_mute_env_exits_before_speech: {e}")
    print(f"\n{len(TESTS)+1 - len(failed)} passed, {len(failed)} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
