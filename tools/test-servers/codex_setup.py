import os, sys
# Creates Codex user tester and libraries for content/Manga and content/Books. Run with tools/codexvenv/bin/python, then restart Codex.
T = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("TEST_SERVERS_DIR", os.path.expanduser("~/test-servers"))
os.environ["CODEX_CONFIG_DIR"] = f"{T}/codex"
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "codex.settings")
import django; django.setup()
from django.contrib.auth.models import User
from codex.models import Library
u, _ = User.objects.get_or_create(username="tester")
u.set_password("mangatest1"); u.is_staff = u.is_superuser = True; u.save()
for d in ("Manga", "Books"):
    Library.objects.get_or_create(path=f"{T}/content/{d}")
print([x.username for x in User.objects.all()], [l.path for l in Library.objects.all()])
a = User.objects.filter(username="admin").first()
if a: a.set_password("mangatest1"); a.save()
from codex.models import Library
print("codex libs:", Library.objects.count())
