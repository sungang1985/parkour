#!/usr/bin/env python3
"""从完整字体中裁剪出游戏用到的汉字，生成体积很小的子集字体。

游戏文本新增汉字后重新运行一次即可（缺字时 Godot 仍会尝试使用系统字体兜底）。

用法：
    pip install fonttools
    # 字体来自 https://github.com/google/fonts （均为 SIL OFL 1.1 授权）
    #   ofl/mashanzheng/MaShanZheng-Regular.ttf
    #   ofl/notosanssc/NotoSansSC[wght].ttf
    python3 tools/make_font_subset.py \
        --title MaShanZheng-Regular.ttf --body "NotoSansSC[wght].ttf"
"""

import argparse
import pathlib

from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

ROOT = pathlib.Path(__file__).resolve().parent.parent
SCAN = ["scripts/**/*.gd", "scenes/**/*.tscn", "tests/**/*.gd", "project.godot"]
EXTRA = "0123456789，。！？：；、“”‘’（）《》·…—←↑→↓◀▶Ⅱ×米分"


def collect_chars() -> str:
    chars = {chr(c) for c in range(0x20, 0x7F)}
    chars.update(EXTRA)
    for pattern in SCAN:
        for path in ROOT.glob(pattern):
            chars.update(ch for ch in path.read_text(encoding="utf-8") if ord(ch) >= 0x80)
    chars.discard("﻿")
    return "".join(sorted(chars))


def write_subset(font: TTFont, text: str, out: pathlib.Path) -> None:
    cmap = font.getBestCmap()
    missing = [ch for ch in text if ord(ch) not in cmap and not ch.isspace()]
    options = subset.Options()
    options.layout_features = ["*"]
    options.name_IDs = ["*"]
    options.notdef_outline = True
    sub = subset.Subsetter(options)
    sub.populate(text=text)
    sub.subset(font)
    font.save(out)
    print(f"{out.relative_to(ROOT)}: {out.stat().st_size // 1024} KB, 缺字 {''.join(missing) or '无'}")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--title", required=True, help="标题字体（马善政毛笔楷书）")
    ap.add_argument("--body", required=True, help="正文字体（思源黑体可变字重版）")
    ap.add_argument("--weight", type=int, default=600, help="正文字重")
    ap.add_argument("--out", default=str(ROOT / "assets" / "fonts"))
    args = ap.parse_args()

    text = collect_chars()
    out = pathlib.Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    print(f"共 {len(text)} 个字符")

    write_subset(TTFont(args.title), text, out / "MaShanZheng-Subset.ttf")
    body = TTFont(args.body)
    if "fvar" in body:
        body = instancer.instantiateVariableFont(body, {"wght": args.weight})
    write_subset(body, text, out / "NotoSansSC-Subset.ttf")


if __name__ == "__main__":
    main()
