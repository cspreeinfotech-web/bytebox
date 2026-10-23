#!/usr/bin/env python3
"""Seeds clearly-labelled demo data for the E2E/screenshot run, or removes it.

usage: seed.py seed   → prints KEY=VALUE lines (demo credentials, ids) for $GITHUB_ENV
       seed.py clean  → deletes demo users (cascades), demo channels/posts, their storage, demo orders
Needs env SUPABASE_URL, SERVICE_KEY. Everything created is tagged "[demo-e2e]" / e2e+…@bytebox.test.
"""
import io, json, os, secrets, subprocess, sys, tempfile, urllib.request, urllib.error
from PIL import Image, ImageDraw, ImageFont

URL = os.environ["SUPABASE_URL"].rstrip("/")
KEY = os.environ["SERVICE_KEY"]
TAG = "[demo-e2e]"
FONT = os.path.join(os.path.dirname(__file__), "..", "..", "mobile", "assets", "fonts", "Poppins-Bold.ttf")


def req(method, path, body=None, headers=None, raw=None):
    h = {"apikey": KEY, "Authorization": f"Bearer {KEY}"}
    data = None
    if raw is not None:
        data = raw
    elif body is not None:
        data = json.dumps(body).encode()
        h["Content-Type"] = "application/json"
    h.update(headers or {})
    r = urllib.request.Request(URL + path, data=data, method=method, headers=h)
    try:
        with urllib.request.urlopen(r, timeout=60) as resp:
            txt = resp.read().decode() or "null"
            return json.loads(txt) if txt.strip().startswith(("{", "[")) else txt
    except urllib.error.HTTPError as e:
        raise SystemExit(f"{method} {path} -> {e.code} {e.read().decode()[:500]}")


def rest(method, table, body=None, query=""):
    return req(method, f"/rest/v1/{table}{query}", body, {"Prefer": "return=representation"})


def upload(bucket, key, data, ctype):
    req("POST", f"/storage/v1/object/{bucket}/{key}", raw=data, headers={"Content-Type": ctype, "x-upsert": "true"})


def thumb(title, c1, c2):
    w, h = 1280, 720
    img = Image.new("RGB", (w, h))
    d = ImageDraw.Draw(img)
    for x in range(w):
        t = x / w
        d.line([(x, 0), (x, h)], fill=tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3)))
    d.text((70, 520), title, font=ImageFont.truetype(FONT, 72), fill=(255, 255, 255))
    b = io.BytesIO()
    img.save(b, "JPEG", quality=85)
    return b.getvalue()


def video(seconds, color):
    out = tempfile.mktemp(suffix=".mp4")
    subprocess.run(["ffmpeg", "-loglevel", "error", "-f", "lavfi", "-i", f"color=c={color}:s=640x360:d={seconds}",
                    "-f", "lavfi", "-i", f"sine=frequency=440:duration={seconds}", "-shortest",
                    "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", out], check=True)
    return open(out, "rb").read()


def create_user(email, password):
    u = req("POST", "/auth/v1/admin/users", {"email": email, "password": password, "email_confirm": True})
    return u["id"]


def seed():
    pw = "Demo-" + secrets.token_urlsafe(10)
    owner_email = f"e2e+creator@bytebox.test"
    viewer_email = f"e2e+viewer@bytebox.test"
    creator = create_user(owner_email, pw)
    viewer = create_user(viewer_email, pw)
    rest("PATCH", "profiles", {"source": "organic", "display_name": "Demo Creator"}, f"?id=eq.{creator}")
    rest("PATCH", "profiles", {"source": "ads", "display_name": "Riya"}, f"?id=eq.{viewer}")

    channels = [
        ("Travel Diaries", "lifestyle", "all", (124, 92, 255), (255, 92, 168)),
        ("Kitchen Stories", "lifestyle", "all", (20, 184, 166), (34, 211, 238)),
        ("Tech in 60s", "tech", "ads", (255, 122, 26), (255, 201, 77)),
    ]
    posts = [
        (0, "Goa Sunset Timelapse", True), (0, "Hidden Waterfalls of Kerala", False),
        (1, "5-Minute Masala Chai", False), (1, "Hyderabadi Biryani Masterclass", True),
        (2, "Phone Camera Tricks", True), (2, "Fastest Way to Back Up Photos", False),
    ]
    ch_ids = []
    for name, cat, aud, c1, c2 in channels:
        row = rest("POST", "channels", {"owner_id": creator, "name": name, "category": cat, "audience": aud,
                                        "description": f"{TAG} Demo channel for screenshots", "review_status": "approved",
                                        "publish_state": "active", "created_via": "admin"})[0]
        ch_ids.append(row["id"])
        rest("POST", "channel_members", {"channel_id": row["id"], "user_id": viewer})
    trailer, main = video(3, "0x7C5CFF"), video(8, "0xFF5CA8")
    for idx, (ci, title, premium) in enumerate(posts):
        c1, c2 = channels[ci][3], channels[ci][4]
        p = rest("POST", "posts", {"channel_id": ch_ids[ci], "author_id": creator, "title": title, "kind": "video",
                                   "description": f"{TAG} {title}", "is_premium": premium, "status": "draft"})[0]
        pid = p["id"]
        upload("media", f"posts/{pid}/main.mp4", main, "video/mp4")
        upload("media", f"posts/{pid}/thumb.jpg", thumb(title, c1, c2), "image/jpeg")
        patch = {"media_key": f"posts/{pid}/main.mp4", "thumbnail_key": f"posts/{pid}/thumb.jpg", "duration_seconds": 8 + idx * 37,
                 "size_bytes": len(main), "status": "published", "published_at": "now()", "view_count": 120 + idx * 431}
        if premium:
            upload("media", f"posts/{pid}/trailer.mp4", trailer, "video/mp4")
            patch["trailer_key"] = f"posts/{pid}/trailer.mp4"
        patch.pop("published_at")
        rest("PATCH", "posts", patch, f"?id=eq.{pid}")
        req("PATCH", f"/rest/v1/posts?id=eq.{pid}", {"published_at": f"2026-10-{20 - idx:02d}T10:00:00Z"})

    # Cloud demo for the viewer (Play build gives 15 GB).
    rest("PATCH", "profiles", {"play_free_cloud": True}, f"?id=eq.{viewer}")
    folders = {}
    for name in ["Photos", "Documents", "Videos", "Work"]:
        folders[name] = rest("POST", "cloud_files", {"user_id": viewer, "name": name, "is_folder": True})[0]["id"]
    files = [("Goa-trip.jpg", "image/jpeg", thumb("Goa trip", (255, 92, 168), (124, 92, 255))),
             ("Resume-2026.pdf", "application/pdf", b"%PDF-1.4\n% demo\n"),
             ("Family-dinner.mp4", "video/mp4", main)]
    for name, mime, data in files:
        fid = rest("POST", "cloud_files", {"user_id": viewer, "name": name, "mime_type": mime, "size_bytes": len(data)})[0]["id"]
        key = f"{viewer}/{fid}"
        upload("cloud", key, data, mime)
        rest("PATCH", "cloud_files", {"storage_key": key, "uploaded": True}, f"?id=eq.{fid}")

    print(f"DEMO_PASSWORD={pw}")
    print(f"DEMO_VIEWER_EMAIL={viewer_email}")
    print(f"DEMO_CREATOR_EMAIL={owner_email}")
    print(f"DEMO_PREMIUM_TITLE=Goa Sunset Timelapse")


def clean():
    users = req("GET", "/auth/v1/admin/users?per_page=200")
    demo = [u for u in users.get("users", []) if (u.get("email") or "").endswith("@bytebox.test")]
    for u in demo:
        uid = u["id"]
        chans = rest("GET", "channels", query=f"?owner_id=eq.{uid}&select=id")
        for c in chans:
            for p in rest("GET", "posts", query=f"?channel_id=eq.{c['id']}&select=id"):
                keys = [f"posts/{p['id']}/{n}" for n in ("main.mp4", "trailer.mp4", "thumb.jpg")]
                req("DELETE", "/storage/v1/object/media", {"prefixes": keys})
        cloud = rest("GET", "cloud_files", query=f"?user_id=eq.{uid}&storage_key=not.is.null&select=storage_key")
        if cloud:
            req("DELETE", "/storage/v1/object/cloud", {"prefixes": [c["storage_key"] for c in cloud]})
        rest("DELETE", "channels", query=f"?owner_id=eq.{uid}")
        try:
            rest("DELETE", "meta_events", query=f"?user_id=eq.{uid}")
        except SystemExit:
            pass  # table exists only after Stage 8 is deployed
        rest("DELETE", "payment_orders", query=f"?user_id=eq.{uid}")
        req("DELETE", f"/auth/v1/admin/users/{uid}")
    print(f"removed {len(demo)} demo users")


if __name__ == "__main__":
    {"seed": seed, "clean": clean}[sys.argv[1]]()
