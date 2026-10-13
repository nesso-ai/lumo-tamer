# 🚀 Anleitung: Proton `lumo-tamer` Setup & Auth-Transfer (Windows → Linux Server)

Diese Anleitung beschreibt den **kompletten Ablauf**: Du baust `lumo-tamer` auf Windows auf, extrahierst **einmalig** eine echte Browser-Session aus Chrome, verschlüsselst sie in eine Vault-Datei und überträgst sie auf einen headless Linux-Server. Dort läuft `lumo-tamer` als OpenAI-kompatibler Server und hält die Session per `autoRefresh` selbstständig am Leben.

Das Helper-Skript **`customized/auth/start-auth.ps1`** automatisiert den kompletten Vorbereitungsteil: Build, Chrome-Start und das spätere Auslesen des Vault-Keys. `lumo-tamer` erzeugt und verwaltet den Verschlüsselungsschlüssel selbst (OS-Keychain). Deine manuellen Schritte sind: Chrome-Login, `tamer auth browser`, im Skript Enter drücken (zeigt den Key) und die Artefakte in `customized/app/sessions/` auf den Server kopieren.

---

## 🎯 Warum dieser Workflow nötig ist

* **Das Problem:** Protons Sicherheitssystem blockiert CLI-Logins (`proton-auth` / Go-Binary) sehr schnell mit Fehlermeldungen (z. B. `422 POST https://mail.proton.me/api/auth/v4 ...` / Code 2028).
* **Die Strategie:** Statt über die CLI einzuloggen, loggst du dich **einmalig** über einen echten Chrome-Browser ein. Die Session wird verschlüsselt gespeichert, zum Server übertragen und dort dauerhaft via `autoRefresh` am Leben gehalten. Auf dem Server ist kein Browser und kein erneuter Login nötig.

---

## 🧭 Der komplette Ablauf im Überblick

1. **Voraussetzungen prüfen** (Windows, PowerShell, Node.js, Chrome, Linux-Server).
2. **Helper-Skript `customized/auth/start-auth.ps1` starten.** Es installiert Abhängigkeiten, baut das Projekt, verknüpft die CLI global und startet Chrome im CDP-Debugging-Modus. Der Verschlüsselungsschlüssel wird NICHT erfragt – `tamer auth` erzeugt ihn automatisch.
3. **Im gestarteten Chrome einloggen** (lumo.proton.me).
4. **`tamer auth browser` ausführen.** Extrahiert die Session, erzeugt den Vault-Key automatisch und schreibt alles verschlüsselt nach `sessions/vault.enc`.
5. **Im Skript Enter drücken.** Zeigt den vom System erzeugten Vault-Key an (aus dem Windows Credential Manager).
6. **Artefakte auf den Server kopieren:** `customized/app/sessions/vault.txt` (Base64-encoded vault) und `customized/app/sessions/lumo-vault-key` (Schlüssel).
7. **Server konfigurieren und starten** (`config.yaml` + Docker Compose).
8. **Funktion testen.**

---

## ✅ Schritt 1: Voraussetzungen

| Voraussetzung | Wofür | Hinweis |
| :--- | :--- | :--- |
| Windows 10/11 | Session-Extraktion & Helper-Skript | Skript läuft mit PowerShell |
| PowerShell | Ausführen von `start-auth.ps1` | In Windows integriert |
| Node.js (inkl. npm) | Build & `tamer`-CLI | `node --version` prüfen |
| Google Chrome (Standardpfad) | Einmaliger Login + CDP | Wird automatisch erkannt |
| Linux-Server mit Docker | Betrieb des Servers | `docker compose` nötig |

> **Hinweis zu Go:** Das Go-Binary `proton-auth` wird automatisch gebaut – entweder mit system-Go (1.24+) oder einem projekt-lokalen Go (wird in `customized/tools/go` heruntergeladen).

---

## � Schritt 2: Helper-Skript `customized/auth/start-auth.ps1` ausführen

Das Skript übernimmt den kompletten Vorbereitungsteil automatisch. Öffne eine PowerShell im Projektordner und starte es:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\customized\auth\start-auth.ps1
```

### Was das Skript automatisch macht

1. **Abhängigkeiten installieren:** `npm install`
2. **Projekt bauen:** `npm run build` (TypeScript-Code)
3. **Go-Binary bauen:** `customized/auth/build-login.ps1` (system-Go 1.24+ oder projekt-lokales Go in `customized/tools/go`)
4. **Konfiguration nach dist kopieren:** `customized/auth/config.yaml` nach `dist/config.yaml`
5. **CLI global verknüpfen:** `npm link` (macht den Befehl `tamer` systemweit verfügbar)
6. **Chrome im CDP-Debugging-Modus starten** mit diesen Flags:

```
--remote-debugging-address=127.0.0.1
--remote-debugging-port=9222
--remote-debugging-allowed-origins=*
--disable-dev-shm-usage
--user-data-dir=<Projektordner>\customized\.profile
```

> ⚠️ **Wichtig:** Der Parameter `--user-data-dir` ist zwingend erforderlich. Das temporäre Profil wird unter `customized/.profile` erstellt und nach Abschluss automatisch gelöscht.

### Wo kommt der Verschlüsselungsschlüssel her?

`lumo-tamer` erzeugt den Vault-Schlüssel **automatisch beim ersten Auth** (32 zufällige Bytes, Base64) und speichert ihn im OS-Keychain (Windows: Credential Manager, macOS: Keychain, Linux: Secret Service). Details: [docs/authentication.md](authentication.md) unter **Security**.

- Der Eintragsname im Windows Credential Manager ergibt sich aus `auth.vault.keychain.service` (hier `lumo-tamer`) und `auth.vault.keychain.account` (hier `vault-key`). **keytar erzeugt daraus das Target `lumo-tamer/vault-key`** (mit Schrägstrich, nicht Unterstrich!).
- Du musst weder einen Schlüssel erfinden noch eingeben: `tamer auth` legt ihn an, wenn er fehlt.

### Fallback: Chrome nicht gefunden

Findet das Skript Chrome nicht unter `C:\Program Files\Google\Chrome\Application\chrome.exe` oder `C:\Program Files (x86)\Google\Chrome\Application\chrome.exe`, zeigt es eine Warnung. Dann startest du Chrome manuell mit den obigen Flags und fährst mit Schritt 3 fort.

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

Die dafür nötige Windows-`config.yaml` wird vom Skript automatisch nach `dist/config.yaml` kopiert und sieht so aus:

```yaml
auth:
  method: "browser"

  vault:
    path: "sessions/vault.enc"
    keychain:
      service: "lumo-tamer"
      account: "vault-key"
    keyFilePath: "/run/secrets/lumo-vault-key"

  browser:
    cdpEndpoint: "http://localhost:9222"

autoRefresh:
  enabled: true
  intervalHours: 20
  onError: true
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

## �️ Schritt 5: Vault-Key auslesen (im Skript)

Gehe zurück zum Terminal, in dem `start-auth.ps1` noch läuft. Dort steht:

```
After running "tamer auth browser" and verifying sessions/vault.enc exists, press Enter to read your vault key (or type N to skip):
```

* **Enter drücken** → das Skript liest den Vault-Key via `customized/auth/read-vault-key.mjs` (nutzt keytar, dieselbe Bibliothek wie `tamer`; `service`/`account` werden aus `config.defaults.yaml` gelesen) und zeigt den **Vault-Key als Base64** an. Notiere ihn dir sicher!
* **`N` eingeben** → der Key wird nicht angezeigt.

> **Tipp:** Du kannst den Key jederzeit selbst auslesen: `node customized/auth/read-vault-key.mjs`

---

## 📦 Schritt 6: Artefakte auf den Server kopieren

Das Skript hat die Artefakte bereits automatisch nach `customized/app/sessions/` kopiert:

| Datei | Zweck | Inhalt |
| :--- | :--- | :--- |
| `customized/app/sessions/vault.txt` | Base64-codierte Vault-Datei | Einfacher zu transportieren als Binärdatei |
| `customized/app/sessions/lumo-vault-key` | Der Schlüssel zum Entschlüsseln | Exakt der Key aus Schritt 5 |

### Auf dem Linux-Server anlegen

Übertrage die Artefakte auf den Linux-Server und entschlüssele die Vault-Datei:

```bash
# Base64-vault.txt entschlüsseln
base64 -d customized/app/sessions/vault.txt > sessions/vault.enc

# Schlüsseldatei anlegen (ohne Zeilenumbruch!)
printf '%s' 'DEIN-VAULT-KEY-AUS-SCHRITT-5' > sessions/lumo-vault-key
chmod 600 sessions/lumo-vault-key
```

> ⚠️ **WICHTIG:** Ohne die passende Schlüsseldatei kann der Server `vault.enc` **nicht** entschlüsseln. Erzeuge die Datei auf dem Server mit `printf`, damit kein Zeilenumbruch dazukommt. Der Inhalt muss **exakt** dem Key aus Schritt 5 entsprechen.

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
| `auth.method: "login"` | Der Server nutzt die mitgebrachte Session (kein CDP-Browser nötig) |
| `auth.vault.path` | Pfad zur entschlüsselten Vault-Datei |
| `auth.vault.keyFilePath` | Pfad zur Key-Datei, die du in Schritt 6 auf dem Server selbst erzeugt hast. Auf Linux wird der Schlüssel **aus der Datei** gelesen, nicht aus einem Credential Manager |
| `auth.autoRefresh.enabled` | Verlängert die Session automatisch, bevor sie abläuft |
| `server.port` | Port des OpenAI-kompatiblen Endpunkts |
| `server.apiKey` | API-Key, den deine Clients verwenden |

> **Hinweis:** Der Inhalt der Datei `sessions/lumo-vault-key` auf dem Server muss **exakt** dem Schlüssel entsprechen, den dir in Schritt 5 angezeigt wurde (`node customized/auth/read-vault-key.mjs`). Erzeuge die Datei am besten direkt auf dem Server mit `printf '%s' '...' > sessions/lumo-vault-key` (ohne Zeilenumbruch am Ende).

### 7.2 Docker Container starten

```bash
# Docker Image pullen und Container im Hintergrund starten
docker compose pull
docker compose up -d
```

---

## � Schritt 8: Funktionsprüfung

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

## 🧹 Schritt 9: Aufräumen auf dem Windows-Rechner (optional)

Nachdem der Server läuft, kannst du auf Windows aufräumen:

1. **Chrome-Prozesse beenden:**
   ```cmd
   taskkill /F /IM chrome.exe
   ```

2. **Temporäres Chrome-Profil löschen:**
   ```cmd
   rmdir /S /Q "customized\.profile"
   ```
   > **Hinweis:** Das Skript `start-auth.ps1` versucht, das Profil automatisch zu löschen. Falls das nicht klappt, kannst du es manuell entfernen.

3. **NPM-Verknüpfung entfernen (optional):**
   ```cmd
   npm unlink -g lumo-tamer
   ```

4. **Tresor-Eintrag prüfen (optional):** Falls du in Schritt 5 `N` gewählt hast, entferne den Eintrag `lumo-tamer/vault-key` über die Anmeldeinformationsverwaltung unter Windows.

---

## ❓ Häufige Probleme

| Problem | Lösung |
| :--- | :--- |
| `tamer auth browser` findet Chrome nicht | Chrome muss mit `--remote-debugging-port=9222` und eigenem `--user-data-dir` laufen (macht das Skript automatisch) |
| Server meldet Entschlüsselungsfehler | `sessions/lumo-vault-key` wurde auf dem Server nicht angelegt oder stimmt nicht mit dem Key aus Schritt 5 (`node customized/auth/read-vault-key.mjs`) überein, oder `auth.vault.keyFilePath` zeigt auf den falschen Pfad |
| Chrome blockiert Remote-Debugging | Immer mit eigenem `--user-data-dir` starten; ohne eigenes Profil blockiert Chrome Port 9222 |
| Go-Build schlägt fehl | Das Skript lädt automatisch Go 1.24 in `customized/tools/go` herunter |
| `vault.txt` enthält nicht-Base64-Inhalt | Stelle sicher, dass `sessions/vault.enc` existiert, bevor du `vault.txt` auf dem Server entschlüsselst |tamer auth browser` findet Chrome nicht | Chrome muss mit `--remote-debugging-port=9222` und eigenem `--user-data-dir` laufen (macht das Skript automatisch) |
| Server meldet Entschlüsselungsfehler | `sessions/lumo-vault-key` wurde auf dem Server nicht angelegt oder stimmt nicht mit dem Key aus Schritt 5 (`node tools/read-vault-key.mjs`) überein, oder `auth.vault.keyFilePath` zeigt auf den falschen Pfad |
| Chrome blockiert Remote-Debugging | Immer mit eigenem `--user-data-dir` starten; ohne eigenes Profil blockiert Chrome Port 9222 |