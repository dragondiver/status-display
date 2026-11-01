<!--
  Gemeinsame Regeln für alle sechs Repos (telefon-ai, heim-agent, mise-en-place,
  rundfunk, sprachkurs, status-display). NICHT HIER BEARBEITEN, wenn du diese Datei in einem
  Repo unter .claude/rules/ liest: Die Quelle liegt auf Florians Mac unter
  ~/Development/claude-konventionen/konventionen.md und wird per sync.sh in
  alle Repos verteilt. Änderungen hier würden beim nächsten Sync überschrieben.
-->

# Konventionen für Florians Repos

Diese Regeln gelten in allen sechs Repos: `telefon-ai`, `heim-agent`,
`mise-en-place`, `rundfunk`, `sprachkurs`, `status-display` (Owner `dragondiver`). Die
`CLAUDE.md` bzw. `AGENTS.md` des jeweiligen Repos geht bei Widerspruch vor.

## Die wichtigste Regel: erst am Code prüfen

Jede Zustandsbehauptung — aus einem Issue, einem Review, einer Routine oder
von dir selbst — wird am Code nachgeprüft, **bevor** daraus Arbeit wird.
Verzeichnis auflisten statt die eine naheliegende Datei lesen:
`ls .github/workflows/` statt nur `ci.yml`, `ls docs/` statt nur der
verlinkten Spec.

Real passiert: mise-en-place#49 („gitleaks läuft nur als pre-push-Hook") war
falsch, `gitleaks.yml` existierte längst — der doppelte Job landete trotzdem
in `main`. mise-en-place#45 listete 13 Sicherheitspunkte, die Hälfte war
erledigt. telefon-ai#46 beschrieb Änderungen, die nicht im Diff waren.

Der Befund „ist längst erledigt" ist genauso wertvoll wie die Umsetzung.
Schreibe ihn als Kommentar ins Issue.

## Board „Development" (GitHub Project #3)

Alle offenen Issues der sechs Repos laufen in **einem** Board:
<https://github.com/users/dragondiver/projects/3>. Die Repos bleiben
getrennt, kein Monorepo, keine zweite Übersicht daneben.

**Spalten:** `Inbox` → `Ideas` → `Watching` → `Backlog` → `Ready` →
`In Progress` → `Review` → `Done`

- **Inbox** — alles Neue. Legst du ein Issue an, gehört es in `Inbox`,
  nicht in `Ideas` oder `Backlog`. Florian sortiert.
- **Watching** — wartet auf Erkenntnis, nicht auf Arbeit. Den Auslöser,
  wann die Karte wieder herauskommt, ins Issue schreiben.
- **Ready** — klar genug zum Anfangen. Eine offene Entscheidung heißt
  `Backlog`, nicht `Ready`.
- **Done** — setzen die Auto-Workflows (Issue geschlossen, PR gemergt).
  Nicht von Hand schieben.

**Autonomy** steuert, was ein Agent allein anfassen darf:

| Wert | Bedeutung |
|---|---|
| `Autonomous` | in einer Session abschließbar, verifizierbar, keine offene Entscheidung |
| `Supervised` | Weggabelung oder Wirkung nach außen (Dienst-Neustart, Deploy, Produktentscheidung) — nur mit Florian im Gespräch |
| `Human-only` | Handgriffe an Geräten, Browser-Flows in Florians Konten, Abwägungen, die Implementieren nicht beantworten darf |

Harte Regeln:

- **Autonomy und Priority nie im Alleingang setzen.** Wert mit Begründung
  vorschlagen, dann warten.
- **Nur `Ready` + `Autonomous` wird ohne Florian umgesetzt.** Ist eine Karte
  `Supervised` oder `Human-only`, oder fehlt das Feld: nicht umsetzen, sondern
  die offene Frage berichten.
- **Priority `High`** nur für echte Außenfläche oder was Florians Familie
  unmittelbar trifft — nicht für „wäre schön".
- Bugs bekommen das Label `bug`, keine eigene Spalte.
- Nur die Orchestrator-Session auf dem Mac besitzt das Board und mergt.
  Agenten und Cloud-Sessions ändern keine Board-Felder, es sei denn, der
  Auftrag sagt es ausdrücklich.

**Entscheidungen festhalten:** Trifft Florian eine Festlegung zu einem Issue,
kommt sie automatisch als Issue-Kommentar — Datum, Entscheidung, Begründung,
ggf. To-do-Liste. Macht sie den Titel falsch, Titel mit anpassen und im
Kommentar vermerken. **Issues schließen nur nach Rückfrage.**

**Fragen an Florian:** Issue-Kommentar mit der Überschrift „Frage an
Florian" und dem Label `question`. Im Chat pro Punkt eine kurze Nachricht
(Info, Vorschlag, Entscheidungsfrage), keine Sammelnachrichten. Nach der
Antwort Label entfernen, Entscheidung als Kommentar festhalten.

**Sub-Issues** bündeln nach „würde ich in einem PR erledigen", nicht nach
Themenähnlichkeit. Anlegen mit `-F` (typisiert), sonst 422:
`gh api --method POST repos/dragondiver/$REPO/issues/$ELTERN/sub_issues -F sub_issue_id="$SID"`

## Pull Requests und Commits

- **Commit-Messages, PR-Titel und -Beschreibungen, Issue-Kommentare auf
  Deutsch.** Fachbegriffe bleiben englisch.
- **Closing-Keywords englisch:** `Closes #12`, `Fixes #12`. `Schließt #12`
  schließt nichts.
- Ein Branch von `origin/main`, ein PR, als **Draft**. Nicht mergen, kein
  Auto-Merge — das macht der Orchestrator nach Prüfung.
- PR-Beschreibung: was und warum, was gemessen wurde, was **nicht** gemessen
  wurde. Keine Behauptungen, die nicht im Diff stehen.
- `main` ist in allen Repos geschützt: PR-Pflicht, Pflicht-Checks, kein
  Force-Push, auch nicht für Admins.
- **Gestapelte PRs:** Wird der untere gemergt, Base des oberen auf `main`
  umziehen, sonst gilt er als gemergt und erreicht `main` nie. Danach in
  `main` nachprüfen.
- Beim Aufräumen einer Routine-PR (`claude/*`, `dependabot/*`): erst
  `git diff origin/main <branch>` — was bleibt nach bereits Gemergtem übrig?
  Zweite Routineläufe duplizieren erste (sprachkurs#27 = #28).

## Verifizieren, nicht behaupten

- Bugfix: Test ohne Fix rot sehen, mit Fix grün. Ein Test, der vorher und
  nachher grün ist, beweist nichts.
- Konfiguration: die Wirkung messen, nicht die Einstellung lesen (Header per
  `curl` am laufenden Server, nicht im Objektliteral).
- Volle Prüfung vor „fertig": `ruff check` + `ruff format --check` + pytest in
  den Python-Repos; in mise-en-place die volle Suite (Unit, Integration, E2E)
  wie in `AGENTS.md` beschrieben — Unit-Tests allein reichen nicht.
- Vorsicht beim Zurücknehmen zum Gegentesten: `git checkout -- datei`
  verwirft uncommittete Arbeit. Danach prüfen, ob der Fix wieder drin ist.

## Architektur: LLM urteilt, Code rechnet

In allen Projekten gilt dieselbe Linie: **das Modell urteilt und extrahiert,
deterministischer Code rechnet und führt Zustand.** Soll ein LLM Zustand
verändern, die Rechenvorschrift als reine Funktion bauen (testbar ohne
Attrappen) und dem Modell nur einen grobkörnigen Aufruf geben
(`sitzung_auswerten()` statt `set_level(6)`).

Der Feind ist stille Drift, nicht der laute Fehler: Nie stillschweigend
verwerfen — ein unbekannter Fall bekommt einen Rückfallwert, keinen
`filter()`. Kein Fehlerpfad endet still; Fehlschläge werden laut.

## Modelle: `MODELLE.md`

Jedes Repo mit KI-Aufrufen führt im Wurzelverzeichnis eine `MODELLE.md`:
Stelle, Zweck, Modell im Code, Wert auf dem Gerät (mit Prüfdatum), Thinking
bzw. reasoning.effort. Wer ein Modell, einen Default oder das Thinking ändert,
ändert die Datei **im selben PR**. Wer einen Gerätewert in 1Password umstellt,
trägt ihn mit Datum nach. Die monatliche Routine „Monatscheck KI-Modelle“
liest die Datei und meldet jede Abweichung zum Code.

## CI ohne Secrets

Die Test-Pipelines brauchen **kein einziges Repository-Secret**, damit
Dependabot-PRs (die keine Secrets bekommen) voll geprüft werden. Externe
Dienste werden gemockt (`monkeypatch.setenv`, `vi.mock`, `page.route()`).
Ein Test mit echtem API-Key kommt hinter einen Marker, der per `addopts`
ausgeschlossen ist (wie `live` und `pi` in telefon-ai). DB-Tests bekommen
einen ephemeren `postgres:16`-Service-Container.

Wiederkehrende Stolpersteine: Werte, die lokal still aus `.env` kommen und in
CI fehlen; Tests, die an der Zeitzone hängen (lokal Europe/Berlin, CI UTC).

## Schnittstelle telefon-ai ↔ mise-en-place

telefon-ai ruft im Gespräch `POST /api/agent/shopping/items` und
`POST /api/agent/recipes` in mise-en-place auf. Es gibt keinen gemeinsamen Typ
und keinen Vertragstest. Wer `createRecipeSchema`
(`mise-en-place/src/lib/validators.ts`) oder eine `/api/agent/*`-Route
anfasst, prüft `telefon-ai/src/kitelefon/agents/recipes.py` mit — und
umgekehrt. Solche Änderungen sind nie `Autonomous`: als Frage berichten.

## Maßstab

Privatprojekte für Florian und seine Familie — kein Business, keine
Nutzermassen. Sicherheit ja (Secrets nicht ins Repo, Security Headers,
Rate Limiting auf teuren KI-Endpunkten, Backups). SBOM, Patching-SLAs,
Compliance-Artefakte, Post-Incident-Prozeduren nein. Bei jeder Empfehlung
fragen, ob sie an Nutzerzahl, Umsatz oder Regulierung hängt — wenn ja,
streichen und begründen.

## Was Agenten nie tun

- Deployen: kein `deploy/push.sh`, kein `ssh` auf `telefon-ki.local` oder
  `raspi-agent.local`, kein `systemctl`. Deploys sind `Supervised`.
- Secrets lesen oder ausgeben; `.env`-Dateien (außer `.env.example`) bleiben
  zu, Sperren werden nicht umgangen.
- Außerhalb des Auftrags fixen. Nebenbefunde gehören in den Bericht.

## In Cloud-Sessions (claude.ai/code)

Eine Cloud-Session sieht nur dieses eine Repo. Das Board ist von dort
**bewusst nicht erreichbar** — es bleibt Mac-only, beim Orchestrator
(Entscheidung 27.09.2026; kein GitHub-Token in der Cloud-Umgebung). Also:
keine Board-Arbeit versuchen und nicht nach Umwegen suchen. Schnittstellen zu
Nachbar-Repos als offene Frage im PR festhalten statt raten. Entscheidungen
und Board-Vorschläge (Spalte, Priority, Autonomy) in den PR-Text oder Bericht
schreiben, damit der Orchestrator sie überträgt.
