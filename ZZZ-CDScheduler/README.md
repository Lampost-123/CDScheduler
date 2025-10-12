# ZZZ-CDScheduler

Standalone cooldown scheduler for World of Warcraft. Schedule cooldowns at exact combat times with a live tracker and boss‑aware list switching.

## Install
- Copy `ZZZ-CDScheduler` → `World of Warcraft/_retail_/Interface/AddOns/`.
- Restart or `/reload`.

## Quick start
- Open the editor: `/cds` (or `/cdscheduler`).
- Enter a list name, select it from the dropdown.
- Paste entries in the left box (one per line):

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
- Options at bottom: Enable, Allow outside raid (testing), Show tracker.
- Click Save. Your lists and selection persist.

## Boss lists & auto‑switching
- Pre‑seeded for Manaforge Omega (Heroic/Mythic per boss):
  - Plexus Sentinel, Loomithar, Soulbinder Naazindhri, Forgeweaver Araz,
    The Soul Hunters, Fractillus, Nexus‑King Salhadaar, Dimensius the All‑Devouring
- Boss lists are protected; “Custom” is freeform.
- Dropdown ordered by boss; “Custom” is last. Difficulty is color‑coded.
- On pull (`ENCOUNTER_START`), the addon auto‑selects the mapped list for the
  encounter + difficulty (Heroic=15, Mythic=16).
- If no mapping exists, the scheduler disables itself unless the selected list is “Custom”.

## Behavior
- A spell is allowed only when elapsed combat time ∈ `[time, time + window]`.
- Spells not in the list are not gated.
- After the final listed time + window, gating is lifted for that spell (free use).
- Tracker shows upcoming icons/timers and the active list name; a small “Scheduler ON” badge appears when active.

## Commands
- `/cds` or `/cdscheduler` to open the editor.

## License
MIT
