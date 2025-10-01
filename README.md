# CDScheduler

## Installation

1. Copy the `CDScheduler` folder into `World of Warcraft/_retail_/Interface/AddOns/`.
2. Restart the game or `/reload`.

## Getting Started

- Open the editor with `/cds`.
- Give your list a name, select it from the dropdown, and paste your entries into the left box using this format (one per line):

```
{time:MM:SS} -  {spell:SPELL_ID}
```

Example:

```
{time:00:02} -  {spell:384631}
{time:00:03} -  {spell:185313}
{time:00:05} -  {spell:121471}
```

- The right panel shows a preview with each spell’s icon and time.
- Set “Window (seconds)” under the preview. Scheduled spells are allowed only in the interval `[time, time + window]`.
- At the bottom:
  - Enable scheduled cooldowns
  - Allow outside raid (testing)
  - Show on-screen tracker
- Click Save. The last selected list is automatically loaded on login/reload.
