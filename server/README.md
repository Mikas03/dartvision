# Server (PocketBase)

Accounts, Historie in der Cloud und Online-Spiele laufen über [PocketBase](https://pocketbase.io) –
eine einzelne Programmdatei mit Datenbank (SQLite), Anmeldung und Echtzeit-Updates.
Die App funktioniert auch ohne Server; der Server ist nur für die Online-Funktionen nötig.

```
server/
├── pb_migrations/   Datenbank-Struktur und Zugriffsregeln (im Repository)
├── test_rules.py    prüft die Zugriffsregeln mit Test-Accounts (läuft auch in GitHub Actions)
├── bin/             PocketBase-Programm (nicht im Repository)
└── pb_data/         Datenbank (nicht im Repository!)
```

**Datenmodell**

| Collection | Inhalt | Wer darf was |
|---|---|---|
| `users` | Accounts (E-Mail, Passwort, Name) | jeder nur sich selbst |
| `games` | Online-Spiele: Code, Gastgeber, Gast, Status, kompletter Spielstand mit Versionsnummer | nur die beiden Mitspieler; Fremde sehen nur wartende Spiele und können sich als Gast eintragen |
| `matches` | Historie: beendete Matches mit jedem Wurf | Besitzer und Mitspieler lesen, nur der Besitzer schreibt |

## Lokal (Windows, zum Entwickeln)

```bash
server\bin\pocketbase.exe serve --http=127.0.0.1:8090 --dir=server/pb_data --migrationsDir=server/pb_migrations
```

Beim ersten Start zeigt PocketBase einen Link, um ein Admin-Konto fürs Dashboard
(`http://127.0.0.1:8090/_/`) anzulegen. In der App unter **Online** die Adresse
`http://127.0.0.1:8090` eintragen (geht nur, wenn die App selbst lokal läuft, z. B. mit
`flutter run -d chrome` – die HTTPS-Version auf GitHub Pages braucht einen HTTPS-Server).

Regeln prüfen: `python server/test_rules.py`

## Raspberry Pi

Getestet ist bisher nur die lokale Variante; die Schritte für den Pi:

1. **PocketBase installieren** (Raspberry Pi OS 64 Bit):
   ```bash
   sudo mkdir -p /opt/dartvision && cd /opt/dartvision
   curl -LO https://github.com/pocketbase/pocketbase/releases/download/v0.40.6/pocketbase_0.40.6_linux_arm64.zip
   echo "d22c66ceb67ca92b7d767f36d826e848a276bcfa3c197ead20bf87c42208984f  pocketbase_0.40.6_linux_arm64.zip" | sha256sum -c
   unzip pocketbase_0.40.6_linux_arm64.zip pocketbase
   ```
   `pb_migrations/` aus diesem Repository nach `/opt/dartvision/pb_migrations` kopieren.

2. **Als Dienst starten** – `/etc/systemd/system/dartvision.service`:
   ```ini
   [Unit]
   Description=Dartvision PocketBase
   After=network-online.target

   [Service]
   User=pi
   WorkingDirectory=/opt/dartvision
   ExecStart=/opt/dartvision/pocketbase serve --http=127.0.0.1:8090 --dir=pb_data --migrationsDir=pb_migrations
   Restart=always

   [Install]
   WantedBy=multi-user.target
   ```
   ```bash
   sudo systemctl enable --now dartvision
   ```

3. **Von außen erreichbar mit HTTPS** über einen
   [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/)
   (keine Portfreigabe im Router nötig, funktioniert auch mit DS-Lite): eigene Domain bei
   Cloudflare, `cloudflared` installieren, Tunnel auf `http://127.0.0.1:8090` zeigen lassen,
   z. B. als `dart.deine-domain.de`. Diese Adresse dann in der App unter **Online** eintragen.

4. **Backup:** Die ganze Datenbank liegt in `pb_data/`. Regelmäßig sichern, z. B. per
   `pocketbase` Dashboard → Settings → Backups (automatische Backups einstellbar) oder per
   cron-Job, der `pb_data` kopiert. Am besten auf einer SSD statt der SD-Karte betreiben.

5. **Updates:** Neue PocketBase-Version herunterladen, Dienst stoppen, Datei ersetzen, starten.
   Neue Migrationen aus dem Repository werden beim Start automatisch angewendet.
