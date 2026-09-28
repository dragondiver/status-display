# Product

## Register

product

## Users
Florian und Kollegen aus seinem Entwicklungsteam, auf ihren Firmen-Macs (GitHub Enterprise, Code-Owner-Reviews als Normalfall, Claude Code und andere Coding-Agenten). Das Dashboard-Fenster liegt neben der eigentlichen Arbeit (IDE, Terminal, Browser) und wird viele Male pro Stunde kurz angesehen, gelegentlich angeklickt. Kollegen haben kein AKP02-Display; für sie ist das Fenster die einzige Ansicht.

## Product Purpose
Zeigen, was gerade auf mich wartet, und mit einem Klick dorthin führen: Review-Anfragen (Extra-Anfragen an mich zuerst, Code-Owner-Anfragen nur solange niemand reviewt hat), eigene PRs mit roter CI oder angeforderten Änderungen, Agenten, die auf mich warten. Später Jira-Tickets (#28). Erfolg: Niemand muss GitHub oder mehrere Terminals durchsuchen, um zu wissen, was als Nächstes dran ist.

## Brand Personality
Ruhig, präzise, hilfsbereit. Ein gutes Werkzeug, das verschwindet, solange nichts zu tun ist, und klar spricht, wenn etwas wartet.

## Anti-references
Keine bunten KPI-Dashboards mit großen Zahlenkacheln. Keine Benachrichtigungsflut. Kein Nachbau der GitHub-Weboberfläche. Kein „Dark Mode, weil Entwickler“.

## Design Principles
1. Dringendes zuerst: Die Reihenfolge ist die Botschaft (wartet auf mich > rot > Rest).
2. Ruhe ist der Normalzustand: Ohne offene Punkte wirkt das Fenster leer und gelassen, nicht kaputt.
3. Ein Klick zum Ziel: Jeder Eintrag führt direkt zum PR, Agenten-Terminal oder Ticket.
4. Gleiche Sprache wie das Display: Orange heißt „wartet auf dich / Extra“, Rot heißt „CI rot“, Grau heißt „veraltet oder erledigt“.
5. Der eigene Status ist Nebensache: ein kleines Etikett, kein Hauptelement.

## Accessibility & Inclusion
Farbe nie als einziges Signal (Orange/Rot immer mit Text oder Symbol). Hell- und Dunkelmodus folgen macOS. Kontrast mindestens WCAG AA. Reduzierte Bewegung respektieren.
