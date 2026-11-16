# mysync

mysync ist eine kleine macOS-App für das Statusmenü (oben rechts neben der Uhr). Sie synchronisiert Ordner zwischen Ihrem Mac und anderen Computern – ausschließlich mit **rsync über SSH**.

## Funktionen

- **Symbol im Statusmenü** mit kleinem Punkt:
  - **grün**: Alle Ordner wurden zuletzt erfolgreich synchronisiert.
  - **rot**: Mindestens ein Ordner wurde zuletzt nicht synchronisiert.
  - kein Punkt: Es ist noch nichts gelaufen.
- **Dropdown** mit einer Zeile pro Computer und Ordner:
  - Computer, Richtung und Ordner, z. B. `NAS → Fotos`
  - Intervall, z. B. „täglich um 12:00 Uhr“, „alle 10 Minuten“ oder „stündlich“
  - letzte Synchronisierung, z. B. „✓ zuletzt vor 5 Min.“
  - **Klick auf eine Zeile** startet die Synchronisierung sofort.
  - Dazu „Alle jetzt synchronisieren“, „Einstellungen …“ und „Beenden“.
- **Intervalle**: alle X Minuten, stündlich oder täglich zu einer festen Uhrzeit. Verpasste Läufe (z. B. weil der Mac schlief) werden nachgeholt.
- **Richtung pro Ordner**: Senden (Mac → Computer) oder Holen (Computer → Mac).
- **Optionen**: `--delete` (Ziel spiegelt die Quelle exakt) und Ausschlussmuster wie `*.tmp`.
- **Intelligente Benachrichtigungen**: Ist ein Computer nicht erreichbar, meldet mysync das **nur, wenn Sie im Netzwerk dieses Computers sind**. Unterwegs mit dem Laptop bleibt es still.
- **Komfortable Einrichtung**: Ordnerauswahl per Dialog, „Aktuelles WLAN übernehmen“, „Aktuelles Subnetz übernehmen“, „Verbindung testen“ und eine Vorschau des rsync-Aufrufs.
- **Beim Anmelden starten** (optional).

## Voraussetzungen

- macOS 14 (Sonoma) oder neuer
- Xcode 15 oder neuer und [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- Auf jedem entfernten Computer: SSH-Zugang und rsync
- Empfohlen: GNU rsync über Homebrew (`brew install rsync`). macOS bringt nur `openrsync` mit. Das funktioniert auch, kann aber weniger. mysync nimmt automatisch `/opt/homebrew/bin/rsync`, wenn es vorhanden ist.

## SSH-Schlüssel einrichten

mysync meldet sich **ohne Passwort** an (`BatchMode=yes`). Dafür braucht es einen SSH-Schlüssel:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/mysync
```

```bash
ssh-copy-id -i ~/.ssh/mysync.pub benutzer@nas.local
```

Ist der entfernte Computer ein Mac, schalten Sie dort unter **Systemeinstellungen → Allgemein → Teilen** die **Entfernte Anmeldung** ein.

In mysync tragen Sie den Schlüssel `~/.ssh/mysync` beim Computer ein und klicken auf **Verbindung testen**.

## Bauen und starten

```bash
xcodegen generate
```

```bash
xcodebuild -project mysync.xcodeproj -scheme mysync -configuration Release -derivedDataPath build build
```

```bash
open build/Build/Products/Release/mysync.app
```

Zum dauerhaften Einsatz kopieren Sie `mysync.app` nach `/Programme` und aktivieren in den Einstellungen „Beim Anmelden starten“.

Alternativ öffnen Sie `mysync.xcodeproj` in Xcode und starten mit ⌘R.

## Bedienung

1. **Einstellungen → Computer → Computer hinzufügen**: Name, Host, Benutzer, Port und SSH-Schlüssel angeben. Optional die Netzwerke des Computers hinterlegen (siehe unten).
2. **Einstellungen → Ordner → Ordner hinzufügen**: Computer wählen, lokalen Ordner auswählen, Zielordner auf dem Computer eintragen, Richtung und Intervall festlegen.
3. Fertig. mysync prüft alle 30 Sekunden und nach dem Aufwachen, ob etwas fällig ist.

Pfade: Es wird immer der **Inhalt** eines Ordners synchronisiert. `~/Fotos` → `/volume1/Fotos` legt also keinen zusätzlichen Unterordner `Fotos/Fotos` an.

## Netzwerkerkennung

Pro Computer können Sie hinterlegen, in welchem Netzwerk er steht:

- **WLAN-Namen (SSID)**, z. B. `Zuhause` und `Zuhause-5G`
- **Subnetze** in CIDR-Schreibweise, z. B. `192.168.1.0/24`. Das hilft, wenn Ihr Mac per Kabel verbunden ist.

Ist der Computer nicht erreichbar, gilt:

| Situation | Status | Benachrichtigung | Punkt |
|---|---|---|---|
| Sie sind im Netzwerk des Computers | nicht erreichbar | ja, einmal pro Ausfall | rot |
| Sie sind woanders | übersprungen | nein | unverändert |
| Kein Netzwerk hinterlegt | nicht erreichbar | ja, einmal pro Ausfall | rot |

Nach einem Ausfall oder einem übersprungenen Lauf versucht mysync es spätestens nach 5 Minuten erneut. So wird ein täglicher Sync nach dem Heimkommen nachgeholt.

**Hinweis zur Ortungsfreigabe:** macOS gibt den WLAN-Namen nur heraus, wenn die App die Ortungsdienste nutzen darf. mysync fragt danach, wenn Sie „Aktuelles WLAN übernehmen“ klicken (oder unter Einstellungen → Allgemein). Ohne Freigabe erkennt mysync das Netzwerk nur über die Subnetze.

## Konfiguration

Die Einstellungen liegen als JSON-Datei unter:

```
~/Library/Application Support/mysync/config.json
```

## Aufbau des Projekts

```
Package.swift            Swift-Package „MySyncCore“ (gesamte Logik, ohne UI)
Sources/MySyncCore/      Modelle, Intervalle, rsync-Befehle, Netzwerk, Zeitsteuerung
Tests/MySyncCoreTests/   Tests
App/                     Statusmenü, Einstellungsfenster, Benachrichtigungen
project.yml              XcodeGen-Beschreibung der App
```

Die App läuft bewusst **ohne App-Sandbox**, weil sie `rsync` und `ssh` als Prozesse startet und auf beliebige Ordner zugreifen muss.

## Tests

```bash
swift test
```

Die Tests decken Folgendes ab: Intervalle (inklusive Tageswechsel und Sommerzeit), den Aufbau der rsync-Argumente, die Netzwerkerkennung (SSID, CIDR), die Benachrichtigungsregeln, die Punktfarbe, die Zeitsteuerung, die Speicherung und die deutschen Texte. Dazu kommen Integrationstests mit echten Prozessen und einem echten rsync-Lauf zwischen zwei temporären Ordnern.

## Lizenz

MIT – siehe [LICENSE](LICENSE).
