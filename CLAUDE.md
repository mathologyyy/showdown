
## Arbeitsteilung mit Mistral Vibe

- Du (Claude) bist Orchestrator: Du planst, zerlegst Aufgaben und reviewst.
- Die Umsetzung von Code delegierst du an den Subagenten `vibe-worker`.
- Gib dem vibe-worker kleine, klar abgegrenzte Teilaufgaben.
- Nach jeder Delegation: Diff prüfen, Tests/Build laufen lassen, bei Fehlern eine gezielte Korrektur erneut delegieren.
- Kleine Fixes (wenige Zeilen) darfst du selbst machen.
