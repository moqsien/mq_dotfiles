import gzip
import json
import os
import re
import subprocess
import sys
import urllib.parse
import urllib.request
import zlib

# ========================================================
# 强制补全图形显示环境变量
# ========================================================
if not os.environ.get("DISPLAY"):
    os.environ["DISPLAY"] = ":0"
if not os.environ.get("WAYLAND_DISPLAY"):
    os.environ["WAYLAND_DISPLAY"] = "wayland-0"
if not os.environ.get("XDG_RUNTIME_DIR"):
    os.environ["XDG_RUNTIME_DIR"] = f"/run/user/{os.getuid()}"
# ========================================================

HEADERS = {
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8",
    "Accept-Encoding": "gzip, deflate",
    "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
    "Connection": "keep-alive",
    "Host": "dict.youdao.com",
    "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/152.0.0.0 Safari/537.36",
    "sec-ch-ua": '"Chromium";v="152", "Not?A_Brand";v="24", "Google Chrome";v="152"',
    "sec-ch-ua-mobile": "?0",
    "sec-ch-ua-platform": '"Linux"',
}


def clean(text):
    """剥掉 <b> </b> 等 HTML 标签"""
    if not isinstance(text, str):
        return str(text)
    return re.sub(r"</?[^>]+>", "", text).strip()


def get_youdao_dict(word):
    url = f"http://dict.youdao.com/jsonapi?q={urllib.parse.quote(word)}"
    req = urllib.request.Request(url, headers=HEADERS)
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            raw_data = response.read()
            encoding = response.info().get("Content-Encoding")
            if encoding == "gzip":
                raw_data = gzip.decompress(raw_data)
            elif encoding == "deflate":
                raw_data = zlib.decompress(raw_data)
            return json.loads(raw_data.decode("utf-8"))
    except Exception as e:
        return {"error": str(e)}


# ---------------- 递归提取工具 ----------------


def _texts_from_l(node):
    """从 l 字段递归提取所有字符串 (兼容 字符串/列表/{"i":[...]} 等任意嵌套)"""
    if isinstance(node, str):
        return [node]
    if isinstance(node, list):
        out = []
        for item in node:
            out += _texts_from_l(item)
        return out
    if isinstance(node, dict):
        out = []
        for v in node.values():
            out += _texts_from_l(v)
        return out
    return []


def _walk_trs(node, defs):
    """递归遍历 ec.trs 的所有嵌套格式"""
    if isinstance(node, list):
        for item in node:
            _walk_trs(item, defs)
    elif isinstance(node, dict):
        if "l" in node:
            for t in _texts_from_l(node["l"]):
                defs.append(clean(t))
        for tr in node.get("tr", []):
            if isinstance(tr, dict):
                pos = tr.get("pos", "")
                texts = []
                if isinstance(tr.get("tr"), list):
                    texts += [clean(x) for x in tr["tr"] if isinstance(x, str)]
                if "l" in tr:
                    texts += [clean(x) for x in _texts_from_l(tr["l"])]
                if texts:
                    defs.append((pos + " " if pos else "") + "; ".join(texts))


# ---------------- 数据提取 ----------------


def extract_phones(data):
    basic = data.get("basic") or {}
    uk = basic.get("uk-phonetic", "")
    us = basic.get("us-phonetic", "")
    ph = basic.get("phonetic", "")
    if uk or us or ph:
        return uk, us, ph
    for src in ("ec", "simple"):
        words = (data.get(src) or {}).get("word", [])
        if isinstance(words, list) and words and isinstance(words[0], dict):
            uk = words[0].get("ukphone", "")
            us = words[0].get("usphone", "")
            if uk or us:
                return uk, us, ""
    return "", "", ""


def extract_prototype(data):
    words = (data.get("ec") or {}).get("word", [])
    if isinstance(words, list):
        for w in words:
            if isinstance(w, dict) and w.get("prototype"):
                return w["prototype"]
    return ""


def extract_definitions(data):
    defs = []
    # basic
    for exp in (data.get("basic") or {}).get("explains", []):
        defs.append(clean(exp))
    # expand_ec
    for word_info in (data.get("expand_ec") or {}).get("word", []):
        pos = word_info.get("pos", "")
        ts = []
        for t in word_info.get("transList", []):
            c = t.get("content") or {}
            txt = c.get("trans") or t.get("trans") or ""
            if txt:
                ts.append(clean(txt))
        if ts:
            defs.append(f"[{pos}] {'; '.join(ts)}" if pos else "; ".join(ts))
    # ec.trs (递归通吃所有格式)
    for w in (data.get("ec") or {}).get("word", []):
        if isinstance(w, dict):
            for group in w.get("trs", []):
                _walk_trs(group, defs)
    # collins 双语释义
    for ce in (data.get("collins") or {}).get("collins_entries", []):
        for entry in (ce.get("entries") or {}).get("entry", []):
            for te in entry.get("tran_entry", []):
                tran = clean(te.get("tran", ""))
                pos = (te.get("pos_entry") or {}).get("pos", "")
                if tran:
                    defs.append(f"[{pos}] {tran}" if pos else tran)
    # 去重保序
    seen = set()
    uniq = []
    for d in defs:
        if d and d not in seen:
            seen.add(d)
            uniq.append(d)
    return uniq


def extract_examples(data, limit=3):
    exs = []
    for word_info in (data.get("expand_ec") or {}).get("word", []):
        for t in word_info.get("transList", []):
            for s in (t.get("content") or {}).get("sents", []):
                orig = clean(s.get("sentOrig", ""))
                trans = clean(s.get("sentTrans", ""))
                if orig:
                    exs.append((orig, trans))
    if not exs:
        for p in (data.get("blng_sents_part") or {}).get("sentence-pair", []):
            orig = clean(p.get("sentence-eng", "") or p.get("sentence", ""))
            trans = clean(p.get("sentence-translation", ""))
            if orig:
                exs.append((orig, trans))
    if not exs:
        for s in (data.get("auth_sents_part") or {}).get("sent", []):
            orig = clean((s.get("foreign") or "").strip())
            if orig:
                exs.append((orig, ""))
    return exs[:limit]


# ---------------- 格式化与弹窗 ----------------


def format_dict_data(data, proto_data=None, prototype=""):
    if "error" in data:
        return f"❌ 请求失败: {data['error']}"

    lines = []
    uk, us, ph = extract_phones(data)
    if uk or us:
        lines.append(f"🇬🇧 [{uk}]   🇺🇸 [{us}]")
    elif ph:
        lines.append(f"🔊 [{ph}]")
    if prototype:
        lines.append(f"↪ 原形: {prototype}")
    if lines:
        lines.append("-" * 45)

    defs = extract_definitions(data)
    if proto_data:
        for d in extract_definitions(proto_data):
            if d not in defs:
                defs.append(d)
    for d in defs[:8]:
        lines.append(f"• {d}")

    exs = extract_examples(data)
    if not exs and proto_data:
        exs = extract_examples(proto_data)
    if exs:
        lines.append("")
        lines.append("✏️ 例句:")
        for orig, trans in exs:
            lines.append(f"  • {orig}")
            if trans:
                lines.append(f"    {trans}")

    web_items = (data.get("web_trans") or {}).get("web-translation", [])
    if web_items:
        lines.append("")
        lines.append("🌐 专业/网络释义:")
        for item in web_items[:3]:
            key = clean(item.get("key", ""))
            vals = [
                clean(t.get("value", ""))
                for t in item.get("trans", [])
                if isinstance(t, dict) and t.get("value")
            ]
            if key and vals:
                lines.append(f"  - {key}: {', '.join(vals)}")

    if not lines and data.get("translation"):
        lines.append("💡 基础翻译:")
        lines.append("  " + ", ".join(data["translation"]))

    if not lines:
        with open("/tmp/sioyek_dict_debug.log", "a") as f:
            f.write(f"[未解析] keys={list(data.keys())}\n")
        return "未找到该词的详细释义。"

    return "\n".join(lines)


def show_popup(word, message):
    safe = message.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    cmd = [
        "zenity",
        "--info",
        f"--title=📖 {word}",
        f"--text={safe}",
        "--width=520",
        "--ok-label=关闭",
    ]
    try:
        if (
            subprocess.run(
                cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
            ).returncode
            == 0
        ):
            return
    except FileNotFoundError:
        pass

    try:
        flat_message = message.replace("\n", " | ")
        subprocess.run(
            ["notify-send", f"📖 {word}", flat_message, "-t", "8000"], check=True
        )
        return
    except Exception:
        pass

    with open("/tmp/sioyek_dict_debug.log", "a") as f:
        f.write(f"[弹窗失败] {word}: {message}\n")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1].strip():
        word = sys.argv[1].strip().strip('"').strip("'").strip()
        data = get_youdao_dict(word)
        prototype = extract_prototype(data)
        proto_data = None
        if prototype and prototype.lower() != word.lower():
            proto_data = get_youdao_dict(prototype)
        show_popup(word, format_dict_data(data, proto_data, prototype))
