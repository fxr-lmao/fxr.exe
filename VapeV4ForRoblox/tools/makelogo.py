#!/usr/bin/env python3
"""Draws the fxr mascot to dist/assets/fxrlogo.png.

The loader installs whatever png sits at that path and uses it for the gui
button, so replacing this drawing is just replacing the file -- this script
only exists so the logo is reproducible rather than a binary nobody can edit.

Shapes are drawn twice, black at full width then grey inset by the stroke,
which is what gives the outlined look without tracing outlines by hand.

    python3 tools/makelogo.py [-o path] [--size 512]
"""

import argparse
import math
import os

from PIL import Image, ImageDraw

INK = (0, 0, 0, 255)
FILL = (236, 236, 236, 255)
STROKE = 15
SUPERSAMPLE = 4


def limb(draw, points, width, colour):
    draw.line(points, fill=colour, width=width, joint="curve")
    for point in (points[0], points[-1]):
        r = width // 2
        draw.ellipse([point[0] - r, point[1] - r, point[0] + r, point[1] + r], fill=colour)


def outlined_limb(draw, points, width, stroke):
    limb(draw, points, width, INK)
    limb(draw, points, width - stroke * 2, FILL)


def outlined_polygon(draw, points, inset):
    draw.polygon(points, fill=INK)
    cx = sum(p[0] for p in points) / len(points)
    cy = sum(p[1] for p in points) / len(points)
    shrunk = []
    for x, y in points:
        dx, dy = x - cx, y - cy
        length = math.hypot(dx, dy) or 1
        shrunk.append((x - dx / length * inset, y - dy / length * inset))
    draw.polygon(shrunk, fill=FILL)


def draw_mascot(size):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    u = size / 550.0  # the source drawing is 550 wide

    def p(x, y):
        return (x * u, y * u)

    stroke = int(STROKE * u)

    # Arms first so the torso overlaps their shoulder ends. Both hang out and
    # down, the left one bending back in at the elbow.
    outlined_limb(d, [p(212, 250), p(112, 278), p(148, 332)], int(74 * u), stroke)
    outlined_limb(d, [p(322, 248), p(432, 292), p(448, 330)], int(74 * u), stroke)

    # Legs mid stride, the left swung forward and the right trailing.
    outlined_limb(d, [p(243, 368), p(178, 470)], int(84 * u), stroke)
    outlined_limb(d, [p(305, 370), p(378, 468)], int(84 * u), stroke)

    # Torso, a touch wider at the hips than the shoulders.
    outlined_polygon(
        d,
        [p(208, 228), p(328, 232), p(344, 382), p(192, 374)],
        stroke,
    )

    # Head, a touch wider than tall.
    head = [p(140, 30), p(415, 235)]
    d.ellipse([head[0][0], head[0][1], head[1][0], head[1][1]], fill=INK)
    d.ellipse(
        [head[0][0] + stroke, head[0][1] + stroke, head[1][0] - stroke, head[1][1] - stroke],
        fill=FILL,
    )

    # Eyes.
    for ex, ey in ((238, 113), (318, 118)):
        r = 9 * u
        d.ellipse([ex * u - r, ey * u - r, ex * u + r, ey * u + r], fill=INK)

    # Smile, a shallow arc rather than a semicircle.
    d.arc(
        [p(178, 95)[0], p(178, 95)[1], p(370, 200)[0], p(370, 200)[1]],
        start=18,
        end=162,
        fill=INK,
        width=int(13 * u),
    )
    return img


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-o", "--out", default="dist/assets/fxrlogo.png")
    ap.add_argument("--size", type=int, default=512)
    args = ap.parse_args()

    img = draw_mascot(args.size * SUPERSAMPLE)
    img = img.resize((args.size, args.size), Image.LANCZOS)

    os.makedirs(os.path.dirname(args.out) or ".", exist_ok=True)
    img.save(args.out)
    print(f"wrote {args.out} ({args.size}x{args.size})")


if __name__ == "__main__":
    main()
