"""Prüft die Zugriffsregeln des PocketBase-Servers mit drei frischen Test-Accounts.

Aufruf (Server muss laufen):  python server/test_rules.py [http://127.0.0.1:8090]
Die Test-Zugangsdaten landen in server/.env.test (nicht im Repository).
"""
import json, secrets, sys, urllib.parse, urllib.request, urllib.error
BASE = (sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8090").rstrip("/") + "/api"

def req(method, path, body=None, token=None):
    r = urllib.request.Request(BASE + path, method=method, data=None if body is None else json.dumps(body).encode(),
                               headers={"Content-Type": "application/json", **({"Authorization": token} if token else {})})
    try:
        with urllib.request.urlopen(r) as resp:
            return resp.status, json.loads(resp.read() or b"{}")
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b"{}")

def user(name):
    email = f"test-{name.lower()}-{secrets.token_hex(3)}@example.test"
    pw = secrets.token_urlsafe(12)
    s, _ = req("POST", "/collections/users/records", {"email": email, "password": pw, "passwordConfirm": pw, "name": name})
    assert s == 200, s
    s, auth = req("POST", "/collections/users/auth-with-password", {"identity": email, "password": pw})
    assert s == 200
    with open("server/.env.test", "a") as f:
        f.write(f"{name}={email} {pw}\n")
    return auth["token"], auth["record"]["id"]

ok = True
def check(label, cond):
    global ok
    ok &= cond
    print(("OK   " if cond else "FAIL ") + label)

a, a_id = user("Anna"); b, b_id = user("Ben"); c, c_id = user("Carl")
code = secrets.token_hex(3).upper()[:6]
s, g = req("POST", "/collections/games/records", {"code": code, "host": a_id, "status": "waiting", "settings": {"mode": "x01"}}, a)
check("Anna legt Spiel an", s == 200)
s, _ = req("POST", "/collections/games/records", {"code": code + "X", "host": a_id, "status": "waiting"}, b)
check("Ben kann kein Spiel im Namen von Anna anlegen", s != 200)
s, lst = req("GET", f"/collections/games/records?filter=" + urllib.parse.quote(f'code="{code}"'), token=b)
check("Ben findet das wartende Spiel per Code", s == 200 and lst["totalItems"] == 1)
s, _ = req("PATCH", f"/collections/games/records/{g['id']}", {"guest": b_id, "host": b_id}, b)
check("Ben kann sich nicht zum Gastgeber machen", s != 200)
s, _ = req("PATCH", f"/collections/games/records/{g['id']}", {"guest": b_id}, b)
check("Ben tritt als Gast bei", s == 200)
s, _ = req("PATCH", f"/collections/games/records/{g['id']}", {"guest": c_id}, c)
check("Carl kann Ben nicht verdrängen", s != 200)
s, _ = req("PATCH", f"/collections/games/records/{g['id']}", {"status": "playing", "state": {"v": 1}, "version": 1}, a)
check("Anna schreibt den Spielstand", s == 200)
s, rec = req("GET", f"/collections/games/records/{g['id']}", token=b)
check("Ben sieht den Spielstand", s == 200 and rec["state"] == {"v": 1})
s, _ = req("GET", f"/collections/games/records/{g['id']}", token=c)
check("Carl sieht das laufende Spiel nicht", s != 200)
s, _ = req("GET", f"/collections/games/records/{g['id']}")
check("Ohne Anmeldung kein Zugriff", s != 200)
s, m = req("POST", "/collections/matches/records", {"owner": a_id, "participants": [a_id, b_id], "matchId": "m1", "mode": "x01", "data": {}}, a)
check("Anna speichert Match in der Historie", s == 200)
s, _ = req("POST", "/collections/matches/records", {"owner": a_id, "participants": [a_id], "matchId": "m1", "data": {}}, a)
check("Doppeltes Match wird abgelehnt", s != 200)
s, lst = req("GET", "/collections/matches/records", token=b)
check("Ben sieht das gemeinsame Match", s == 200 and lst["totalItems"] == 1)
s, lst = req("GET", "/collections/matches/records", token=c)
check("Carl sieht es nicht", s == 200 and lst["totalItems"] == 0)
s, _ = req("DELETE", f"/collections/matches/records/{m['id']}", token=b)
check("Ben kann Annas Match nicht löschen", s != 204)
sys.exit(0 if ok else 1)
