from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H = 1080, 1920
TOP, BOT = (0x1B, 0x2E, 0x25), (0x2E, 0x7D, 0x5B)
GOLD = (0xFF, 0xB5, 0x35)

B = lambda s: ImageFont.truetype("NanumGothic-Bold.ttf", s)
R = lambda s: ImageFont.truetype("NanumGothic-Regular.ttf", s)

# 배경 그라데이션
bg = Image.new("RGB", (W, H))
d = ImageDraw.Draw(bg)
for y in range(H):
    t = (y / H) ** 0.85
    d.line([(0, y), (W, y)], fill=tuple(int(TOP[i] + (BOT[i] - TOP[i]) * t) for i in range(3)))

# 알림 패널 크롭
src = Image.open("notif_src.png").crop((30, 900, 1050, 1575))
cw = 940
card = src.resize((cw, int(src.height * cw / src.width)), Image.LANCZOS)

# 라운드 마스크
rad = 36
mask = Image.new("L", card.size, 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, card.width - 1, card.height - 1], rad, fill=255)

cx, cy = (W - card.width) // 2, 760

# 그림자
sh = Image.new("RGBA", (W, H), (0, 0, 0, 0))
ImageDraw.Draw(sh).rounded_rectangle(
    [cx, cy + 14, cx + card.width, cy + card.height + 14], rad, fill=(0, 0, 0, 110))
bg = Image.alpha_composite(bg.convert("RGBA"), sh.filter(ImageFilter.GaussianBlur(22))).convert("RGB")
bg.paste(card, (cx, cy), mask)

d = ImageDraw.Draw(bg)
ctr = lambda y, txt, f, fill: d.text((W // 2, y), txt, font=f, fill=fill, anchor="ma")

# 헤드라인
ctr(150, "앱을 열지 않아도", B(76), (255, 255, 255))
ctr(250, "알림이 먼저 옵니다", B(76), GOLD)

# 서브
ctr(392, "접수 오픈 · 새 강좌 · 마감 후 재오픈까지", R(38), (215, 232, 222))
ctr(452, "관심 조건에 맞으면 자동으로 알려드려요", R(38), (215, 232, 222))

# 하단 배지 (반투명 — RGBA 오버레이로 합성해야 알파가 먹는다)
chips = ["지역 필터", "대상 필터", "바로 신청"]
f = B(34)
gap, padx, hgt = 22, 36, 76
ws = [d.textlength(c, font=f) + padx * 2 for c in chips]
x = (W - (sum(ws) + gap * (len(chips) - 1))) // 2
y = cy + card.height + 96

ov = Image.new("RGBA", (W, H), (0, 0, 0, 0))
od = ImageDraw.Draw(ov)
for c, w in zip(chips, ws):
    od.rounded_rectangle([x, y, x + w, y + hgt], hgt // 2, fill=(255, 255, 255, 38),
                         outline=(255, 255, 255, 110), width=2)
    od.text((x + w / 2, y + hgt / 2), c, font=f, fill=(255, 255, 255, 255), anchor="mm")
    x += w + gap
bg = Image.alpha_composite(bg.convert("RGBA"), ov).convert("RGB")

d = ImageDraw.Draw(bg)
ctr = lambda yy, txt, ff, fill: d.text((W // 2, yy), txt, font=ff, fill=fill, anchor="ma")
ctr(H - 150, "회원가입 없음 · 광고 없음 · 무료", R(36), (196, 220, 206))

bg.save("../shot_notification.png")
print("saved", bg.size)
