import os
# Points Calibre-Web at $TEST_SERVERS_DIR/calibre/library and renames its first-run admin. Run with tools/cwvenv/bin/python.
import re, sys, requests
T = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("TEST_SERVERS_DIR", os.path.expanduser("~/test-servers")); B = "http://localhost:8083"
s = requests.Session()
def csrf(html):
    m = re.search(r'name="csrf_token"[^>]*value="([^"]+)"', html) or re.search(r'value="([^"]+)"[^>]*name="csrf_token"', html)
    return m.group(1) if m else None
def login(u, p):
    r = s.get(f"{B}/login")
    r = s.post(f"{B}/login", data={"username": u, "password": p, "csrf_token": csrf(r.text), "submit": ""}, allow_redirects=True)
    return "logout" in r.text.lower() or r.url.rstrip("/") != f"{B}/login"
ok = login("admin", "admin123") or login("tester", "mangatest1")
print("login", ok)
r = s.get(f"{B}/admin/dbconfig")
tok = csrf(r.text)
r = s.post(f"{B}/ajax/simulatedbchange", data={"config_calibre_dir": f"{T}/calibre/library", "csrf_token": tok}, headers={"X-CSRFToken": tok})
print("simulate", r.status_code, r.text[:200])
r = s.post(f"{B}/admin/dbconfig", data={"config_calibre_dir": f"{T}/calibre/library", "csrf_token": tok, "submit": ""}, headers={"X-CSRFToken": tok})
print("dbconfig", r.status_code, r.url, re.findall(r'class="alert[^"]*"[^>]*>([^<]+)', r.text)[:3])
r = s.get(f"{B}/admin/user/1"); tok = csrf(r.text)
form = {"name": "tester", "email": "tester@example.com", "password": "mangatest1", "locale": "en", "default_language": "all", "csrf_token": tok, "submit": ""}
for k in re.findall(r'name="(show_\d+|admin_role|download_role|upload_role|edit_role|passwd_role|edit_shelf_role|viewer_role)"[^>]*checked', r.text): form[k] = "on"
r = s.post(f"{B}/admin/user/1", data=form)
print("user", r.status_code, re.findall(r'class="alert[^"]*"[^>]*>([^<]+)', r.text)[:3])
