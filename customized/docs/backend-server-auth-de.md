# 🚀 Anleitung: Proton `lumo-tamer` Setup & Auth-Transfer (Windows → Linux Server)

Diese Anleitung beschreibt den **kompletten Ablauf**: Du baust `lumo-tamer` auf Windows auf, extrahierst **einmalig** eine echte Browser-Session aus Chrome, verschlüsselst sie in eine Vault-Datei und überträgst sie auf einen headless Linux-Server. Dort läuft `lumo-tamer` als OpenAI-kompatibler Server und hält die Session per `autoRefresh` selbstständig am Leben.

Das Helper-Skript **`tools/start-auth.ps1`** automatisiert den kompletten Vorbereitungsteil: Build, Chrome-Start und das spätere Auslesen des Vault-Keys. `lumo-tamer` erzeugt und verwaltet den Verschlüsselungsschlüssel selbst (OS-Keychain). Deine manuellen Schritte sind: Chrome-Login, `tamer auth browser`, im Skript Enter drücken (zeigt den Key) und `sessions/vault.enc` auf den Server kopieren.

---

## 🎯 Warum dieser Workflow nötig ist

* **Das Problem:** Protons Sicherheitssystem blockiert CLI-Logins (`proton-auth` / Go-Binary) sehr schnell mit Fehlermeldungen (z. B. `422 POST https://mail.proton.me/api/auth/v4 ...` / Code 2028).
* **Die Strategie:** Statt über die CLI einzuloggen, loggst du dich **einmalig** über einen echten Chrome-Browser ein. Die Session wird verschlüsselt gespeichert, zum Server übertragen und dort dauerhaft via `autoRefresh` am Leben gehalten. Auf dem Server ist kein Browser und kein erneuter Login nötig.

---

## 🧭 Der komplette Ablauf im Überblick

1. **Voraussetzungen prüfen** (Windows, PowerShell, Node.js, Chrome, Linux-Server).
2. **Helper-Skript `tools/start-auth.ps1` starten.** Es installiert Abhängigkeiten, baut das Projekt, verknüpft die CLI global und startet Chrome im CDP-Debugging-Modus. Der Verschlüsselungsschlüssel wird NICHT erfragt – `tamer auth` erzeugt ihn automatisch.
3. **Im gestarteten Chrome einloggen** (lumo.proton.me).
4. **`tamer auth browser` ausführen.** Extrahiert die Session, erzeugt den Vault-Key automatisch und schreibt alles verschlüsselt nach `sessions/vault.enc`.
5. **Im Skript Enter drücken.** Zeigt den vom System erzeugten Vault-Key an (aus dem Windows Credential Manager).
6. **`sessions/vault.enc` auf den Server kopieren** und dort die Schlüsseldatei `sessions/lumo-vault-key` mit dem angezeigten Key erzeugen.
7. **Server konfigurieren und starten** (`config.yaml` + Docker Compose).
8. **Optional aufräumen und Funktion testen.**

---

## ✅ Schritt 1: Voraussetzungen

| Voraussetzung | Wofür | Hinweis |
| :--- | :--- | :--- |
| Windows 10/11 | Session-Extraktion & Helper-Skript | Skript läuft mit PowerShell |
| PowerShell | Ausführen von `start-auth.ps1` | In Windows integriert |
| Node.js (inkl. npm) | Build & `tamer`-CLI | `node --version` prüfen |
| Google Chrome (Standardpfad) | Einmaliger Login + CDP | Wird automatisch erkannt |
| Linux-Server mit Docker | Betrieb des Servers | `docker compose` nötig |

> **Hinweis zu Go:** Das Go-Binary `proton-auth` wird nur gebaut, wenn Go installiert ist. Ohne Go baut das Projekt trotzdem, schreibt aber eine Warnung.

---

## � Schritt 2: Helper-Skript `tools/start-auth.ps1` ausführen

Das Skript übernimmt den kompletten Vorbereitungsteil automatisch. Öffne eine PowerShell im Projektordner und starte es:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\start-auth.ps1
```

### Was das Skript automatisch macht

1. **Abhängigkeiten installieren:** `npm install`
2. **Projekt bauen:** `npm run build:all` (TypeScript-Code + Go-Binary `dist/proton-auth`)
3. **Konfiguration nach dist kopieren:** `config.defaults.yaml` nach `dist/`
4. **CLI global verknüpfen:** `npm link` (macht den Befehl `tamer` systemweit verfügbar)
5. **Chrome im CDP-Debugging-Modus starten** mit diesen Flags:

```
--remote-debugging-address=127.0.0.1
--remote-debugging-port=9222
--remote-debugging-allowed-origins=*
--disable-dev-shm-usage
--user-data-dir=<Projektordner>\.chrome-dev-profile
```

> ⚠️ **Wichtig:** Der Parameter `--user-data-dir` ist zwingend erforderlich. Ohne eigenes Profil blockiert Chrome das Remote-Debugging auf Port 9222 laut Sicherheitsrichtlinie.

### Wo kommt der Verschlüsselungsschlüssel her?

`lumo-tamer` erzeugt den Vault-Schlüssel **automatisch beim ersten Auth** (32 zufällige Bytes, Base64) und speichert ihn im OS-Keychain (Windows: Credential Manager, macOS: Keychain, Linux: Secret Service). Details: [docs/authentication.md](authentication.md) unter **Security**.

- Der Eintragsname im Windows Credential Manager ergibt sich aus `auth.vault.keychain.service` (hier `lumo-tamer`) und `auth.vault.keychain.account` (hier `vault-key`). **keytar erzeugt daraus das Target `lumo-tamer/vault-key`** (mit Schrägstrich, nicht Unterstrich!).
- Du musst weder einen Schlüssel erfinden noch eingeben: `tamer auth` legt ihn an, wenn er fehlt.

### Fallback: Chrome nicht gefunden

Findet das Skript Chrome nicht unter `C:\Program Files\Google\Chrome\Application\chrome.exe`, zeigt es eine Warnung. Dann startest du Chrome manuell mit den obigen Flags und fährst mit Schritt 3 fort.

---

## 🌐 Schritt 3: Im gestarteten Chrome einloggen

1. Gehe im neu geöffneten Chrome-Fenster zu **[lumo.proton.me](https://lumo.proton.me)**.
2. Logge dich ganz normal mit deinen Proton-Zugangsdaten ein.
3. Lasse das Chrome-Fenster geöffnet, solange Schritt 4 läuft.

---

## 🔑 Schritt 4: Session extrahieren (`tamer auth browser`)

Öffne ein zweites Terminal im Projektordner und führe aus:

```powershell
tamer auth browser
```

Was dabei passiert:
1. `lumo-tamer` verbindet sich über CDP mit dem laufenden Chrome (`http://127.0.0.1:9222`).
2. Es liest die angemeldete Session aus dem Browser.
3. Es verschlüsselt die Session mit dem Schlüssel aus dem Windows-Tresor.
4. Die verschlüsselte Datei landet unter `sessions/vault.enc`.

Die dafür nötige Windows-`config.yaml` sieht so aus (lokal im Projektverzeichnis):

```yaml
auth:
  method: "browser"

  vault:
    path: "sessions/vault.enc"
    keychain:
      service: "lumo-tamer"
      account: "vault-key"

  browser:
    # 127.0.0.1 statt localhost, um IPv6-Probleme (::1 ECONNREFUSED) unter Windows zu vermeiden
    cdpEndpoint: "http://127.0.0.1:9222"
```

> ⚠️ **Achtung:** Diese `config.yaml` gilt nur für die Extraktion unter Windows. Auf dem Server gilt eine andere Konfiguration (siehe Schritt 7)!

Nach erfolgreicher Extraktion prüfe den Inhalt von `sessions/`:

```powershell
ls sessions\
```

Es muss mindestens diese Datei existieren:

| Datei | Zweck |
| :--- | :--- |
| `sessions/vault.enc` | Die verschlüsselte Proton-Session |

Der Schlüssel liegt nicht als Datei vor – `lumo-tamer` hat ihn automatisch erzeugt und im Windows Credential Manager gespeichert (`lumo-tamer/vault-key`). Notiere ihn dir in Schritt 5.

---

## 🗑️ Schritt 5: Vault-Key auslesen (im Skript)

Gehe zurück zum Terminal, in dem `start-auth.ps1` noch läuft. Dort steht:

```
After running "tamer auth browser" and verifying sessions/vault.enc exists, press Enter to read your vault key (or type N to skip):
```

* **Enter drücken** → das Skript liest den Vault-Key via `tools/read-vault-key.mjs` (nutzt keytar, dieselbe Bibliothek wie `tamer`; `service`/`account` werden aus `config.defaults.yaml` gelesen) und zeigt den **Vault-Key als Base64** an. Notiere ihn dir sicher!
* **`N` eingeben** → der Key wird nicht angezeigt.

> **Tipp:** Du kannst den Key jederzeit selbst auslesen: `node tools/read-vault-key.mjs`

---

## 📦 Schritt 6: Was auf dem Server anlegen bzw. kopieren

Übertrage die **eine** erzeugte Datei von Windows auf den Linux-Server und lege die **Schlüsseldatei manuell** an:

| Was | Zweck | Herkunft |
| :--- | :--- | :--- |
| `sessions/vault.enc` | Die verschlüsselte Proton-Session | Kopieren von Windows (per scp/Rsync/WinSCP) |
| `sessions/lumo-vault-key` | Der Schlüssel zum Entschlüsseln von `vault.enc` | **Manuell auf dem Server erzeugen** – exakt der Key aus Schritt 5 |

> ⚠️ **WICHTIG:** Ohne die passende Schlüsseldatei kann der Server `vault.enc` **nicht** entschlüsseln. Erzeuge die Datei auf dem Server mit `printf`, damit kein Zeilenumbruch dazukommt:

```bash
printf '%s' 'DEIN-VAULT-KEY-AUS-SCHRITT-5' > sessions/lumo-vault-key
chmod 600 sessions/lumo-vault-key
```

Tipp: `sessions/vault.enc` kopierst du per `scp`:

```bash
scp sessions/vault.enc user@dein-server:/pfad/zu/lumo-tamer/sessions/
```

---

## ⚙️ Schritt 7: Server konfigurieren und starten (Linux)

### 7.1 `config.yaml` auf dem Server anpassen

```yaml
auth:
  # Auf dem Server nutzen wir "login" als Fallback (kein CDP-Browser nötig)
  method: "login"

  vault:
    path: "sessions/vault.enc"
    keyFilePath: "sessions/lumo-vault-key"

  autoRefresh:
    enabled: true
    intervalHours: 20
    onError: true

server:
  port: 3003
  apiKey: "dein-sicherer-api-key"
  apiModelName: "lumo"
```

Erklärung der wichtigsten Parameter:

| Parameter | Bedeutung |
| :--- | :--- |
| `auth.method: "login"` | Der Server loggt nicht selbst ein, er nutzt die mitgebrachte Session |
| `auth.vault.path` | Pfad zur kopierten Vault-Datei |
| `auth.vault.keyFilePath` | Pfad zur Key-Datei, die du in Schritt 6 auf dem Server selbst erzeugt hast. Auf Linux wird der Schlüssel **aus der Datei** gelesen, nicht aus einem Credential Manager |
| `auth.autoRefresh.enabled` | Verlängert die Session automatisch, bevor sie abläuft |
| `server.port` | Port des OpenAI-kompatiblen Endpunkts |
| `server.apiKey` | API-Key, den deine Clients verwenden |

> **Hinweis:** Der Inhalt der Datei `sessions/lumo-vault-key` auf dem Server muss **exakt** dem Schlüssel entsprechen, den dir in Schritt 5 angezeigt wurde (`node tools/read-vault-key.mjs`). Erzeuge die Datei am besten direkt auf dem Server mit `printf '%s' '...' > sessions/lumo-vault-key` (ohne Zeilenumbruch am Ende).

### 7.2 Docker Container starten

```bash
# Docker Image pullen und Container im Hintergrund starten
docker compose pull
docker compose up -d
```

---

## 🧹 Schritt 8: Aufräumen auf dem Windows-Rechner (optional)

Nachdem der Server läuft, kannst du auf Windows aufräumen:

1. **Chrome-Prozesse beenden:**
   ```cmd
   taskkill /F /IM chrome.exe
   ```

2. **Temporäres Chrome-Profil löschen:**
   ```cmd
   rmdir /S /Q "customized/.profile"
   ```

3. **NPM-Verknüpfung entfernen (optional):**
   ```cmd
   npm unlink -g lumo-tamer
   ```

4. **Tresor-Eintrag prüfen (optional):** Falls du in Schritt 5 `N` gewählt hast, entferne den Eintrag `lumo-tamer/vault-key` über die Anmeldeinformationsverwaltung unter Windows.

---

## 🧪 Schritt 9: Funktionsprüfung

Teste die Verbindung vom Windows-Rechner (oder einem beliebigen Client im Netzwerk). Ersetze `<DEINE-SERVER-IP>` durch die IP-Adresse deines Linux-Servers (z. B. `192.168.1.100`):

```bash
curl http://<DEINE-SERVER-IP>:3003/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer dein-sicherer-api-key" \
  -d '{
    "model": "lumo-max",
    "messages": [
      {"role": "user", "content": "Wer bist du?"}
    ]
  }'
```

* **Erfolgskriterium:** Das Modell antwortet sauber als Proton Lumo.
* **Ergebnis:** Die Session wird von `lumo-tamer` auf dem Linux-Server automatisch im Hintergrund verlängert. Der Browser-Login unter Windows muss **nicht** wiederholt werden.

---

## ❓ Häufige Probleme

| `CMDKEY: Falscher Parameter` bei der Tresor-Erstellung | Nicht mehr relevant: `tamer` erzeugt den Tresor-Eintrag selbst (Target `lumo-tamer/vault-key` mit Schrägstrich). Das Helper-Skript schreibt keine Einträge mehr |
| `tamer auth browser` findet Chrome nicht | Chrome muss mit `--remote-debugging-port=9222` und eigenem `--user-data-dir` laufen (macht das Skript automatisch) |
| Server meldet Entschlüsselungsfehler | `sessions/lumo-vault-key` wurde auf dem Server nicht angelegt oder stimmt nicht mit dem Key aus Schritt 5 (`node tools/read-vault-key.mjs`) überein, oder `auth.vault.keyFilePath` zeigt auf den falschen Pfad |
| Chrome blockiert Remote-Debugging | Immer mit eigenem `--user-data-dir` starten; ohne eigenes Profil blockiert Chrome Port 9222 |