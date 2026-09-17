#!/usr/bin/env python3
"""生成静态标定叠图与资源报告，不模拟或截图苹果物理引擎。"""
from __future__ import annotations
import hashlib
import json
import math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
RECIPES = json.loads((ROOT / "Validation/recipes.json").read_text())
FONT_PATH = "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"
# 本机没有此字体时使用默认字体；不向工程复制字体文件。
try:
    FONT = ImageFont.truetype(FONT_PATH, 23)
    SMALL = ImageFont.truetype(FONT_PATH, 16)
except OSError:
    FONT = SMALL = ImageFont.load_default()


def asset(name: str) -> Path:
    return ROOT / "Assets.xcassets" / (name + ".imageset") / (name + ".png")


def capsule_polygons(rect: list) -> list[list[tuple[float, float]]]:
    (x, y), (w, h) = rect
    r, cx = w / 2, x + w / 2
    upper, lower = y + r, y + h - r
    top = [(cx + r * math.cos(math.pi + i * math.pi / 6),
            upper + r * math.sin(math.pi + i * math.pi / 6)) for i in range(7)]
    bottom = [(cx + r * math.cos(i * math.pi / 6),
               lower + r * math.sin(i * math.pi / 6)) for i in range(7)]
    return [[(x, upper), (x + w, upper), (x + w, lower), (x, lower)], top, bottom]


def main() -> None:
    canvas = Image.new("RGB", (1500, 1120), "white")
    draw = ImageDraw.Draw(canvas)
    draw.text((28, 15), "完整内腔与实体几何标定 · 非引擎运行截图", font=FONT, fill=(30, 40, 45))
    draw.text((28, 52), "粉色：实际内壁　青色：开口参考　橙色：出生点　绿色：实体复合碰撞轮廓", font=SMALL, fill=(80, 85, 90))
    reports = []
    for index, recipe in enumerate(RECIPES):
        offset = index * 500
        mapping = recipe["container"]["mapping"]
        scene_w, scene_h = mapping["sceneSize"]
        source_w, source_h = mapping["sourceSize"]
        ox, oy = mapping["origin"]
        scene = Image.new("RGBA", (int(scene_w), int(scene_h)), "white")
        container = recipe["container"]
        image = Image.open(asset(container["layers"][0]["asset"])).convert("RGBA")
        scene.alpha_composite(image, (int(ox), int(scene_h - oy - source_h)))
        sd = ImageDraw.Draw(scene)
        def point(p): return (ox + p[0], scene_h - oy - source_h + p[1])
        sd.line([point(p) for p in container["innerWall"]], fill=(229, 0, 116), width=4)
        sd.line([point(p) for p in container["mouth"]], fill=(0, 168, 176), width=3)
        sx, sy = recipe["policy"]["spawn"]["center"]
        sy = scene_h - sy
        sd.ellipse((sx-6, sy-6, sx+6, sy+6), fill=(249, 134, 23))
        scale = min(450 / scene_w, 670 / scene_h)
        scene = scene.resize((round(scene_w * scale), round(scene_h * scale)), Image.Resampling.LANCZOS)
        canvas.paste(scene.convert("RGB"), (offset + (500-scene.width)//2, 142))
        draw.text((offset+25, 100), recipe["title"], font=FONT, fill=(30, 40, 45))
        g, skin = recipe["entity"]["geometry"], recipe["skins"][0]
        token_image = Image.open(asset(skin["asset"])).convert("RGBA")
        (x, y), (w, h) = skin["contentRect"]
        token = token_image.crop((x, y, x+w, y+h))
        # 绘制的是相同参考图框中的几何，不根据图片透明度推导碰撞轮廓。
        (gx, gy), _ = g["referenceFrame"]
        td = ImageDraw.Draw(token)
        for piece in g["pieces"]:
            if "circle" in piece:
                c = piece["circle"]; cx, cy = c["center"]; r = c["radius"]
                td.ellipse((cx-gx-r,cy-gy-r,cx-gx+r,cy-gy+r), outline=(0,185,102),width=3)
            else:
                polys = [piece["convexPolygon"]["_0"]] if "convexPolygon" in piece else capsule_polygons(piece["capsule"]["frame"])
                for polygon in polys:
                    pts = [(px-gx,py-gy) for px,py in polygon]
                    td.line(pts+[pts[0]],fill=(0,185,102),width=3)
        token.thumbnail((190,210),Image.Resampling.LANCZOS)
        canvas.paste(token,(offset+(500-token.width)//2,865),token)
        draw.text((offset+25,825), f"内壁 {len(container['innerWall'])} 点 · 上限 {recipe['policy']['capacity']} 个",font=SMALL,fill=(70,80,85))
        reports.append({"recipe":recipe["id"],"wall_points":len(container["innerWall"]),
                        "full_depth_pixels":max(p[1] for p in container["innerWall"]),
                        "entity_geometry":g,"runtime_physics_tested":False})
    canvas.save(ROOT / "Validation/geometry-calibration.png")
    assets = []
    for p in sorted((ROOT/"Assets.xcassets").rglob("*.png")):
        image = Image.open(p)
        assets.append({"path":str(p.relative_to(ROOT)),"pixels":list(image.size),
                       "sha256":hashlib.sha256(p.read_bytes()).hexdigest()})
    (ROOT/"Validation/asset-report.json").write_text(json.dumps(assets,ensure_ascii=False,indent=2))
    (ROOT/"Validation/geometry-report.json").write_text(json.dumps(reports,ensure_ascii=False,indent=2))


if __name__ == "__main__":
    main()
