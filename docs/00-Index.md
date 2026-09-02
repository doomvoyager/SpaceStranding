# Space Stranding

Entry point. Everything else hangs off this.

- [[01-Pillars]] - pitch, tone, constraints, hard nos
- [[Decision-Log]] - settled arguments and rejected ideas. **Check before
  re-proposing anything.**
- [[The-Planet]] - the world spec every constant derives from
- [[Visual-Direction]] - the look, and the one decision it all hangs off
- [[Debug-Panel]] - F1 in game. Every tunable on a slider
- [[Placement]] - spawn markers and the ground snap. Drag things, don't type
  coordinates
- `00-Inbox/` is the drop zone. Clear it at session start.

---

## Now

Maximum three. If you want a fourth, something finishes or gets demoted first.

```dataview
TASK
FROM "02-Systems" OR "03-Content" OR "04-Art"
WHERE !completed AND contains(text, "#now")
GROUP BY file.link
```

## Next

```dataview
TASK
FROM "02-Systems" OR "03-Content" OR "04-Art"
WHERE !completed AND contains(text, "#next")
GROUP BY file.link
```

---

## Blocking questions

Answer these before building the thing they gate.

```dataview
TASK
FROM "02-Systems" OR "03-Content" OR "04-Art"
WHERE !completed AND contains(text, "#blocking")
GROUP BY file.link
```

## Waiting on a playtest

Tuning questions a human on the controls would settle in an evening.

```dataview
TASK
FROM "02-Systems" OR "03-Content" OR "04-Art"
WHERE !completed AND contains(text, "#playtest")
GROUP BY file.link
```

## Other open questions

```dataview
TASK
FROM "02-Systems" OR "03-Content" OR "04-Art"
WHERE !completed
  AND contains(text, "#question")
  AND !contains(text, "#blocking")
  AND !contains(text, "#playtest")
GROUP BY file.link
```

---

## Build status

`godot:` is the drift detector. **If it's empty, the system isn't built** -
that's the whole point of the field. Status vocabulary is documented in
[[System-Note]].

```dataview
TABLE WITHOUT ID
  file.link AS "System",
  status AS "Status",
  godot AS "Godot",
  verified AS "Verified"
FROM "02-Systems"
SORT status ASC, file.name ASC
```

### Content & art

```dataview
TABLE WITHOUT ID
  file.link AS "Note",
  status AS "Status",
  godot AS "Godot",
  verified AS "Verified"
FROM "03-Content" OR "04-Art"
SORT status ASC, file.name ASC
```

## Stale notes

Systems not verified against the actual project in over 30 days. Drift lives
here.

```dataview
TABLE WITHOUT ID
  file.link AS "Note",
  status AS "Status",
  verified AS "Last verified"
FROM "02-Systems" OR "03-Content" OR "04-Art"
WHERE verified AND date(today) - date(verified) > dur(30 days)
SORT verified ASC
```

---

## Backlog

Everything else still open. This is the pile - don't read it looking for work,
read it when deciding what gets promoted.

```dataview
TASK
FROM "02-Systems" OR "03-Content" OR "04-Art"
WHERE !completed
  AND !contains(text, "#now")
  AND !contains(text, "#next")
  AND !contains(text, "#question")
GROUP BY file.link
```
