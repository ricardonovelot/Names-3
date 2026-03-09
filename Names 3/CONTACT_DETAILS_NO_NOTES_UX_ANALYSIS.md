# Contact Details — No Notes UX Analysis

## Current State

When a contact has **no notes**, the detail view shows:

1. **Header**: Photo (or camera CTA), name, tags, met date
2. **Summary field**: "Main Note" placeholder — editable inline
3. **Notes section**: Empty — `ForEach(activeNotesForList)` renders nothing

### UX Issues

| Issue | Impact |
|-------|--------|
| **Dead space** | The notes section occupies no visible UI when empty. User scrolls past summary into blank area. |
| **No affordance** | New users may not realize notes can be added. QuickInput bar at bottom is the primary entry point but isn't discoverable. |
| **Cognitive load** | "Main Note" vs "Notes" — two similar concepts. Summary is always visible; notes are hidden until added. |
| **Action gap** | No explicit CTA to add a note. Relies on user noticing the QuickInput bar. |

---

## A/B Test: Top Section Layout When No Notes

**Hypothesis:** Different layouts for the "top" content (below header) when a contact has no notes will affect:
- Note creation rate
- Time to first note
- Perceived usefulness of the app

### Layout Options

| Option | Description | Pros | Cons |
|--------|-------------|------|------|
| **Summary First** (current) | Summary field prominent, notes section empty (no UI). | Familiar, minimal. | No guidance; empty feel. |
| **Empty State CTA** | When no notes, show a ContentUnavailableView-style card: "No notes yet" + "Use the bar below to add notes". Tappable to expand QuickInput. | Clear affordance; teaches the flow. | Extra UI; may feel redundant once user knows. |
| **Add Note Banner** | Prominent tappable banner above summary: "Add your first note" — taps expand QuickInput. | Strong CTA; action-oriented. | More visual weight. |
| **Summary Only** | When no notes, hide the notes section entirely. Summary is the only content. | Clean; no dead space. | Notes may feel secondary. |

---

## Recommended A/B Variants for Settings

1. **Summary First** — Default. Current behavior.
2. **Empty State Prompt** — ContentUnavailableView when no notes; tap to focus QuickInput.
3. **Add Note Banner** — Tappable "Add your first note" card above summary.

**Settings path:** Settings → Usage → Contact details (no notes)

---

## Metrics to Track (Future)

- % of contacts with ≥1 note (by layout variant)
- Time from contact open to first note added
- QuickInput expansion rate when viewing contact with no notes
