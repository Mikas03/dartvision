# dartvision

Automatischer Dartzähler mit **einer** Kamera (Handy oder Webcam). Erst als Python-Prototyp am PC,
später als Handy-App.

**App ausprobieren:** https://mikas03.github.io/dartvision/ (auf dem iPhone in Safari öffnen,
dann Teilen → „Zum Home-Bildschirm“).

Bei jedem Push auf `main` laufen alle Tests (Python und Flutter); sind sie grün, wird die
Web-App automatisch neu gebaut und veröffentlicht (`.github/workflows/deploy.yml`).

## Projektstruktur

```
dart/
├── src/dartvision/
│   ├── board.py         Scheibengeometrie, Punkte aus Position (mm) berechnen
│   ├── calibration.py   Homographie: Kamerabild (px) <-> Scheibe (mm)
│   ├── detection.py     Darterkennung per Differenzbild + Spitzenschätzung
│   ├── game.py          X01-Spiellogik (501, Double-Out, Bust, Undo)
│   ├── overlay.py       Raster, Treffer und Spielstand ins Bild zeichnen
│   ├── synthetic.py     Testvideos mit virtueller Kamera und bekannten Ergebnissen
│   ├── evaluate.py      Erkennung gegen bekannte Ergebnisse messen
│   └── __main__.py      Kommandozeile (calibrate / play / synth / evaluate)
├── tests/               pytest-Tests für Scoring, Spiel und Kalibrierung
├── app/                 Flutter-App (Zähler, später mit Kamera)
│   ├── lib/models/      Hit, X01-Spiellogik, Checkout-Vorschläge
│   ├── lib/screens/     Spiel einrichten, Spielbildschirm
│   ├── lib/widgets/     Tastenfeld, Punktetafel
│   └── test/            Tests für Logik und Oberfläche
└── data/
    ├── videos/          eigene Testaufnahmen (nicht im Git)
    └── images/          Standbilder, z. B. für späteres ML-Training
```

## Einrichten

```bash
python -m venv .venv
.venv\Scripts\activate
pip install -e ".[dev]"
pytest
```

## Benutzung

**1. Kalibrieren:** Kamera fest aufstellen, dann im Standbild die Außenkante des Doppelrings
jeweils in der Mitte der Felder **20, 6, 3, 11** anklicken (oben, rechts, unten, links).
Das eingeblendete Raster muss auf der Scheibe liegen, dann mit `s` speichern.

```bash
python -m dartvision calibrate --source 0
```

**2. Spielen:**

```bash
python -m dartvision play --source 0 --players Anna Ben --grid
```

`--source` ist ein Kameraindex (`0`, `1`, ...) oder eine Videodatei. Das Handy kann man z. B. per
DroidCam / Iriun als Webcam nutzen oder einfach Videos aufnehmen und in `data/videos/` legen.

| Taste / Maus | Funktion |
|---|---|
| Linksklick | Dart manuell an dieser Stelle eintragen (Korrektur) |
| `u` | letzten Dart der Aufnahme zurücknehmen |
| `n` | Aufnahme beenden / nächster Spieler |
| `r` | Scheibe ist leer: Referenzbild neu setzen (z. B. nach Lichtänderung) |
| `g` | Raster ein/aus |
| Leertaste | Pause (bei Videodateien) |
| `q` | beenden |

## Testen ohne Dartboard

`synth` erzeugt ein Video mit virtueller Kamera, gezeichneter Scheibe und 3D-Darts. Zu jedem
Dart wird die echte Einstichstelle gespeichert, `evaluate` misst damit die Erkennung.

```bash
python -m dartvision synth --out data/videos/synth.mp4 --turns 20
python -m dartvision evaluate --video data/videos/synth.mp4
python -m dartvision play --source data/videos/synth.mp4 --calibration data/videos/synth.calibration.json --grid
```

Nützliche Stellschrauben für `synth`: `--yaw` / `--pitch` (Kamerawinkel), `--distance`,
`--noise`, `--no-shadows`, `--seed`. Mit `evaluate --calib-noise 3` simuliert man, dass die
Kalibrierpunkte um ein paar Pixel daneben angeklickt wurden.

Was synthetische Videos **nicht** abbilden: echte Darts und Flights, Reflexionen, Kamera-
Autofokus/Belichtung, Bewegungsunschärfe, wackelndes Stativ. Gute Werte hier sind also eine
Voraussetzung, aber noch kein Beweis für echte Videos.

## Flutter-App

Flutter liegt unter `C:\Users\mikas\flutter` (nicht im PATH, daher voller Pfad).

```bash
cd app
C:\Users\mikas\flutter\bin\flutter test
C:\Users\mikas\flutter\bin\flutter run -d chrome
```

Aktuell: X01 (301/501/701), Single/Double Out, beliebig viele Spieler, Eingabe per Tastenfeld,
Rückgängig auch über Aufnahmen hinweg, Checkout-Vorschläge, Average. Die Kamera-Erkennung soll
später dieselbe Methode `X01Game.throwDart()` aufrufen wie das Tastenfeld.

## Kamera in der App (iPhone)

Startbildschirm → Kamera-Symbol oben rechts. Funktioniert nur über HTTPS, also über die
GitHub-Pages-Adresse (nicht über den lokalen Server im WLAN).

1. Handy fest aufstellen (Stativ), Scheibe vollständig im Bild.
2. Die Außenkante des Doppelrings jeweils in der Mitte der **20, 6, 3, 11** antippen.
   Punkte lassen sich danach verschieben; das Raster muss auf der Scheibe liegen.
3. Aufs Board tippen zeigt das Feld an dieser Stelle – so prüft man die Kalibrierung.
4. **Aufnehmen** speichert ein Video, **Kalibrierung** die passende JSON-Datei
   (auf dem iPhone landen beide in der Dateien-App unter „Downloads“).

**Erkennung an** startet die Live-Erkennung (ca. 10 Bilder/s): erkannte Darts erscheinen mit
Feld im Bild, nach dem Ziehen der Darts wird die Liste geleert. **Scheibe ist leer** setzt das
Referenzbild neu (z. B. nach Lichtänderung).

Ohne Kamera und Board: Film-Symbol oben rechts → **Demo-Szene**. Sie spielt eine synthetische
Szene aus dem Python-Generator ab (`app/assets/demo_scene`) und lässt die Erkennung darauf laufen.

Auswerten mit dem Python-Prototyp:

```bash
python -m dartvision play --source data/videos/dart_20261025_220000.mp4 --calibration data/videos/dart_20261025_220000.calibration.json --grid
```

Die Kalibrierung wird auch im Browser gespeichert und ist beim nächsten Öffnen wieder da.

## Wie die Erkennung funktioniert

1. Ein Referenzbild der Scheibe wird gespeichert.
2. Sobald das Bild nach einer Bewegung wieder ruhig ist, wird es mit der Referenz verglichen.
3. Eine kleine Änderung ist ein neuer Dart. Die Hauptachse aller geänderten Pixel wird bestimmt;
   das schmale Ende ist die Spitze, das breite der Flight.
4. Die Spitze wird per Homographie in Scheibenkoordinaten umgerechnet → Feld + Punkte.
5. Sieht das Bild wieder aus wie die leere Scheibe, wurden die Darts gezogen.
   Sehr große Änderungen (Hand/Person im Bild) werden ignoriert.

## Nächste Schritte

- [ ] Eigene Testvideos aufnehmen, Schwellwerte in `DetectorConfig` anpassen
- [x] Genauigkeit messen: synthetische Videos + `evaluate`
- [ ] Schatten auf dunklen/roten Feldern besser herausfiltern (häufigster Fehler im synthetischen
      Test: Spitze wird entlang des Schattens zu weit unten geschätzt)
- [ ] Verdeckung durch mehrere Darts besser behandeln
- [ ] Automatische Kalibrierung (Doppelring/Segmentdrähte selbst finden)
- [ ] ML-Ansatz testen (YOLO-Keypoints, siehe DeepDarts-Paper und -Datensatz)
- [ ] Weitere Spielmodi (Cricket, Around the Clock), Checkout-Vorschläge
- [x] Flutter-App mit manueller Eingabe
- [ ] App aufs Handy bringen (Android Studio / SDK installieren)
- [x] Kamera in der App: Vorschau, Kalibrierung, Testvideos aufnehmen
- [ ] Echte Testvideos aufnehmen (ausgedrucktes Board + Zahnstocher reicht) und auswerten
- [x] Erkennung in der App (`app/lib/vision/detector.dart`, gleiche Logik wie `detection.py`;
      `app/test/detector_test.dart` und `tests/test_fixture.py` prüfen auf derselben Szene,
      dass beide Versionen dasselbe Ergebnis liefern)
- [ ] Erkennung im Spiel: erkannte Darts direkt in den Zähler übernehmen
