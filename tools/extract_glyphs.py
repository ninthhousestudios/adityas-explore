#!/usr/bin/env python3
"""
Extract planet glyph SVG path data from gandiva/glyphs.py into standalone SVG files.
Each glyph gets a square viewBox computed from path bounding-box estimation.
"""

import math
import os
import re
import sys

sys.path.insert(0, os.path.expanduser("~/nhs/soft/astrology/gandiva"))
from gandiva.glyphs import PLANET_GLYPHS


def estimate_path_bounds(path_d: str, start_x: float = 0, start_y: float = 0):
    """
    Bounding-box estimation by tracking cursor through relative SVG path commands.
    Handles: m, l, c, a, z and implicit lineto after m.
    """
    min_x, min_y = start_x, start_y
    max_x, max_y = start_x, start_y
    cx, cy = start_x, start_y

    num_re = re.compile(r"[+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?")

    tokens = path_d.strip()
    cmd = "l"  # default after m

    def update(x, y):
        nonlocal min_x, min_y, max_x, max_y
        min_x = min(min_x, x)
        min_y = min(min_y, y)
        max_x = max(max_x, x)
        max_y = max(max_y, y)

    update(cx, cy)

    pos = 0
    while pos < len(tokens):
        ch = tokens[pos]
        if ch in " ,\t\n\r":
            pos += 1
            continue
        if ch.isalpha():
            cmd = ch
            pos += 1
            continue

        nums = []
        temp_pos = pos
        while temp_pos < len(tokens):
            m = num_re.match(tokens, temp_pos)
            if m:
                nums.append(float(m.group()))
                temp_pos = m.end()
                while temp_pos < len(tokens) and tokens[temp_pos] in " ,\t\n\r":
                    temp_pos += 1
                if temp_pos < len(tokens) and tokens[temp_pos].isalpha():
                    break
            else:
                break

        if not nums:
            pos += 1
            continue

        pos = temp_pos

        if cmd == "m":
            idx = 0
            if len(nums) >= 2:
                cx += nums[0]
                cy += nums[1]
                update(cx, cy)
                idx = 2
            cmd = "l"
            while idx + 1 < len(nums):
                cx += nums[idx]
                cy += nums[idx + 1]
                update(cx, cy)
                idx += 2

        elif cmd == "M":
            idx = 0
            if len(nums) >= 2:
                cx = nums[0]
                cy = nums[1]
                update(cx, cy)
                idx = 2
            cmd = "L"
            while idx + 1 < len(nums):
                cx = nums[idx]
                cy = nums[idx + 1]
                update(cx, cy)
                idx += 2

        elif cmd == "l":
            idx = 0
            while idx + 1 < len(nums):
                cx += nums[idx]
                cy += nums[idx + 1]
                update(cx, cy)
                idx += 2

        elif cmd == "L":
            idx = 0
            while idx + 1 < len(nums):
                cx = nums[idx]
                cy = nums[idx + 1]
                update(cx, cy)
                idx += 2

        elif cmd == "c":
            idx = 0
            while idx + 5 < len(nums):
                update(cx + nums[idx], cy + nums[idx + 1])
                update(cx + nums[idx + 2], cy + nums[idx + 3])
                cx += nums[idx + 4]
                cy += nums[idx + 5]
                update(cx, cy)
                idx += 6

        elif cmd == "C":
            idx = 0
            while idx + 5 < len(nums):
                update(nums[idx], nums[idx + 1])
                update(nums[idx + 2], nums[idx + 3])
                cx = nums[idx + 4]
                cy = nums[idx + 5]
                update(cx, cy)
                idx += 6

        elif cmd == "a":
            idx = 0
            while idx + 6 < len(nums):
                rx = abs(nums[idx])
                ry = abs(nums[idx + 1])
                ex = cx + nums[idx + 5]
                ey = cy + nums[idx + 6]
                # Extend bounds by radius from chord midpoint (tighter than both-endpoints).
                mx = (cx + ex) / 2
                my = (cy + ey) / 2
                update(mx - rx, my - ry)
                update(mx + rx, my + ry)
                cx = ex
                cy = ey
                idx += 7

        elif cmd in ("z", "Z"):
            pass
        else:
            pass

    return min_x, min_y, max_x, max_y


def glyph_to_svg(name: str, glyph: dict) -> str:
    shift_x, shift_y = glyph["shift"]
    paths = glyph["paths"]

    all_min_x, all_min_y = float("inf"), float("inf")
    all_max_x, all_max_y = float("-inf"), float("-inf")

    path_elements = []
    for path_d, dx, dy in paths:
        start_x = shift_x + dx
        start_y = shift_y + dy
        bx0, by0, bx1, by1 = estimate_path_bounds(path_d, start_x, start_y)
        all_min_x = min(all_min_x, bx0)
        all_min_y = min(all_min_y, by0)
        all_max_x = max(all_max_x, bx1)
        all_max_y = max(all_max_y, by1)
        path_elements.append((path_d, start_x, start_y))

    pad = 2.0
    raw_w = (all_max_x - all_min_x) + pad * 2
    raw_h = (all_max_y - all_min_y) + pad * 2

    # Square viewBox centered on the glyph.
    dim = max(raw_w, raw_h)
    center_x = (all_min_x + all_max_x) / 2
    center_y = (all_min_y + all_max_y) / 2
    vx = center_x - dim / 2
    vy = center_y - dim / 2

    sw = dim * 0.065

    lines = [
        f'<svg xmlns="http://www.w3.org/2000/svg" '
        f'viewBox="{vx:.2f} {vy:.2f} {dim:.2f} {dim:.2f}" '
        f'fill="none" stroke="#e0d8c8" stroke-width="{sw:.2f}" '
        f'stroke-linecap="round" stroke-linejoin="round">',
    ]
    for path_d, sx, sy in path_elements:
        lines.append(f'  <path d="m {sx},{sy} {path_d}"/>')
    lines.append("</svg>")
    return "\n".join(lines)


def main():
    out_dir = os.path.expanduser("~/adityas/explore/assets/glyphs/planets")
    os.makedirs(out_dir, exist_ok=True)

    name_map = {
        "Sun": "sun",
        "Moon": "moon",
        "Mercury": "mercury",
        "Venus": "venus",
        "Mars": "mars",
        "Jupiter": "jupiter",
        "Saturn": "saturn",
        "Uranus": "uranus",
        "Neptune": "neptune",
        "Pluto": "pluto",
        "Chiron": "chiron",
        "Lilith": "lilith",
        "Rahu": "rahu",
        "Ketu": "ketu",
    }

    for display_name, glyph_data in PLANET_GLYPHS.items():
        filename = name_map.get(display_name, display_name.lower())
        svg = glyph_to_svg(display_name, glyph_data)
        path = os.path.join(out_dir, f"{filename}.svg")
        with open(path, "w") as f:
            f.write(svg)
        print(f"  {filename}.svg  {svg.split('viewBox=')[1].split('\"')[1]}")

    print(f"\nWrote {len(PLANET_GLYPHS)} glyphs to {out_dir}")


if __name__ == "__main__":
    main()
