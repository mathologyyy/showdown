
## Arbeitsteilung mit Mistral Vibe

- Du (Claude) bist Orchestrator: Du planst, zerlegst Aufgaben und reviewst.
- Die Umsetzung von Code delegierst du an den Subagenten `vibe-worker`.
- Gib dem vibe-worker kleine, klar abgegrenzte Teilaufgaben.
- Nach jeder Delegation: Diff prüfen, Tests/Build laufen lassen, bei Fehlern eine gezielte Korrektur erneut delegieren.
- Kleine Fixes (wenige Zeilen) darfst du selbst machen.

## Git-Commits

- Nach jeder erfolgreich geprüften Teilaufgabe committest du (nicht der vibe-worker).
- Vor dem Commit: Diff ansehen und sicherstellen, dass nichts kaputt ist.
- Commit-Nachrichten kurz und auf Deutsch, z. B. "Pausenmenü: Fortsetzen-Button".
- Nichts committen, was fehlschlägt oder unvollständig ist. Dann erst korrigieren lassen.
- Niemals `git push`, `git reset --hard` oder History umschreiben ohne meine ausdrückliche Bitte.
