from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H = 1080, 1920
TOP, BOT = (0x1B, 0x2E, 0x25), (0x2E, 0x7D, 0x5B)
GOLD = (0xFF, 0xB5, 0x35)
B = lambda s: ImageFont.truetype("NanumGothic-Bold.ttf", s)
R = lambda s: ImageFont.truetype("NanumGothic-Regular.ttf", s)

def bg_grad():
    bg = Image.new("RGB", (W, H)); d = ImageDraw.Draw(bg)
    for y in range(H):
        t = (y / H) ** 0.85
        d.line([(0, y), (W, y)], fill=tuple(int(TOP[i] + (BOT[i]-TOP[i])*t) for i in range(3)))
    return bg

def compose(src, l1, l2, sub, out, crop_top=78, crop_bot=128, fit=False):
    bg = bg_grad()
    ph = Image.open(src).convert("RGB")
    ph = ph.crop((0, crop_top, ph.width, ph.height - crop_bot))
    top_y = 470
    maxh = H - top_y - 96
    tw = 792
    sh_ = int(ph.height * tw / ph.width)
    if fit and sh_ > maxh:                     # 전체가 보이게 축소(contain)
        tw = int(ph.width * maxh / ph.height); sh_ = maxh
    ph = ph.resize((tw, sh_), Image.LANCZOS)
    if not fit and ph.height > maxh:           # 스크롤 목록은 하단 크롭 OK
        ph = ph.crop((0, 0, ph.width, maxh))
    px = (W - ph.width) // 2
    py = top_y + max(0, (maxh - ph.height)//2)
    rad = 30
    mask = Image.new("L", ph.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0,0,ph.width-1,ph.height-1], rad, fill=255)
    shdw = Image.new("RGBA",(W,H),(0,0,0,0))
    ImageDraw.Draw(shdw).rounded_rectangle([px, py+16, px+ph.width, py+ph.height+16], rad, fill=(0,0,0,120))
    bg = Image.alpha_composite(bg.convert("RGBA"), shdw.filter(ImageFilter.GaussianBlur(26))).convert("RGB")
    bg.paste(ph, (px, py), mask)
    d = ImageDraw.Draw(bg)
    ctr = lambda y,t,f,c: d.text((W//2,y),t,font=f,fill=c,anchor="ma")
    ctr(140, l1, B(74), (255,255,255))
    ctr(240, l2, B(74), GOLD)
    ctr(372, sub, R(37), (206,226,214))
    bg.save(out); print("saved", out, ph.size)

compose("s03.jpg",        "열려 있는 강좌를", "한눈에 모아서", "서울 공공강좌 1,000여 개를 실시간으로", "shot1_list.png")
compose("s02.jpg",        "내 조건에 맞는", "강좌만 골라서", "지역·대상·무료·키워드로 필터", "shot2_filter.png", fit=True)
compose("s01.jpg",        "곧 열릴 강좌는", "미리 알람 예약", "접수 시작 10분 전, 광클 준비 끝", "shot3_upcoming.png")
compose("shot_detail.jpg","탭 한 번으로", "신청·위치까지", "예약 페이지 직행 · 지도로 위치 확인", "shot4_detail.png", crop_top=1090, crop_bot=120, fit=True)
