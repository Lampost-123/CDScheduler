# CDScheduler

## Install
- Copy `CDScheduler` → `World of Warcraft/_retail_/Interface/AddOns/`.
- Restart or `/reload`.

## Quick start
- Open the editor: `/cds`.
- Enter a list name, select it from the dropdown.
- Paste entries in the left box (one per line) or directly from Lorrgs:

```text
{time:MM:SS} - {spell:SPELL_ID}
```

Example:

```text
{time:00:02} - {spell:384631}
{time:00:03} - {spell:185313}
{time:00:05} - {spell:121471}
```

- The right panel shows a live preview with icons and times.
- Set “Window (seconds)” under the preview.
- Click Save. Your lists and selection persist.

## Boss lists & auto‑switching
- Pre‑seeded for Manaforge Omega (Heroic/Mythic per boss):
  - Plexus Sentinel, Loomithar, Soulbinder Naazindhri, Forgeweaver Araz,
    The Soul Hunters, Fractillus, Nexus‑King Salhadaar, Dimensius the All‑Devouring
- Boss lists are protected; “Custom” is freeform.

## Behavior
- A spell is allowed only when elapsed combat time ∈ `[time, time + window]`.
- Spells not in the list are not gated.
- After the final listed time + window, gating is lifted for that spell (free use).
- Tracker shows upcoming icons/timers and the active list name; a small “Scheduler ON” badge appears when active.

## Commands
- `/cds` to open the editor.

