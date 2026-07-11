#!/usr/bin/env python3
"""강좌 알리미 런처 아이콘 생성기 (cairosvg 벡터 → mipmap 5종).
종(Material notifications path, 골드) + 뿔테 안경 + 학사모(마스코트). 초록 라운드 배경.
frac = 종이 배경에서 차지하는 비율(원형 마스크 안전선 ~0.72). 실행: python3 tools/make_icon.py [frac]
"""
import sys, os
import cairosvg
from io import BytesIO
from PIL import Image, ImageDraw

GREEN = "#2E7D5B"; GOLD = "#FFB535"; BLACK = "#2A2A2A"; DARK = "#233A2E"
BELL = "M12 22c1.1 0 2-.9 2-2h-4c0 1.1.9 2 2 2zm6-6v-5c0-3.07-1.63-5.64-4.5-6.32V4c0-.83-.67-1.5-1.5-1.5s-1.5.67-1.5 1.5v.68C7.64 5.36 6 7.92 6 11v5l-2 2v1h16v-1l-2-2z"

def svg(size, frac):
    scale = size * frac / 24
    tx = (size - 24 * scale) / 2
    ty = (size - 24 * scale) / 2 + size * 0.035  # 학사모 공간
    r = size * 0.22
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 {size} {size}">
      <rect width="{size}" height="{size}" rx="{r}" ry="{r}" fill="{GREEN}"/>
      <g transform="translate({tx},{ty}) scale({scale})"><path d="{BELL}" fill="{GOLD}"/>
        <g stroke="{BLACK}" stroke-width="1.1" fill="none" stroke-linejoin="round">
          <rect x="7.4" y="9.6" width="3.5" height="3.0" rx="1.2"/><rect x="13.1" y="9.6" width="3.5" height="3.0" rx="1.2"/>
          <line x1="10.9" y1="10.9" x2="13.1" y2="10.9"/></g></g>
      <g transform="translate({size/2},{ty + 2.2*scale})">
        <polygon points="0,{-size*0.115} {size*0.155},{-size*0.045} 0,{size*0.025} {-size*0.155},{-size*0.045}" fill="{BLACK}"/>
        <path d="M {-size*0.078},{-size*0.03} Q 0,{size*0.035} {size*0.078},{-size*0.03} L {size*0.062},{-size*0.058} L {-size*0.062},{-size*0.058} Z" fill="{DARK}"/>
        <circle cx="0" cy="{-size*0.047}" r="{size*0.013}" fill="{GOLD}"/>
        <line x1="0" y1="{-size*0.047}" x2="{size*0.125}" y2="{-size*0.047}" stroke="{GOLD}" stroke-width="{size*0.009}"/>
        <line x1="{size*0.125}" y1="{-size*0.047}" x2="{size*0.125}" y2="{size*0.032}" stroke="{GOLD}" stroke-width="{size*0.009}"/>
        <circle cx="{size*0.125}" cy="{size*0.038}" r="{size*0.019}" fill="{GOLD}"/></g></svg>'''

def render(size, frac):
    png = cairosvg.svg2png(bytestring=svg(size, frac).encode(), output_width=size, output_height=size)
    return Image.open(BytesIO(png)).convert("RGBA")

def main():
    frac = float(sys.argv[1]) if len(sys.argv) > 1 else 0.70
    res = os.path.join(os.path.dirname(__file__), "..", "app", "android", "app", "src", "main", "res")
    for dpi, px in {'mdpi':48,'hdpi':72,'xhdpi':96,'xxhdpi':144,'xxxhdpi':192}.items():
        im = render(px, frac)
        im.save(os.path.join(res, f'mipmap-{dpi}', 'ic_launcher.png'))
        im.save(os.path.join(res, f'mipmap-{dpi}', 'ic_launcher_round.png'))
    print(f"아이콘 frac={frac} 5종 생성 완료")

if __name__ == "__main__":
    main()
