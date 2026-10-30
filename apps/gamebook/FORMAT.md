# The `.story` format

A plain UTF-8 text file the Gamebook app reads. Write one by hand, or convert a Twine or Ink story
on the [tools site](https://omer-faruq-xteink.github.io/touch-licorice-apps/tools/gamebook/).

```
title: The Lighthouse
author: Jane Doe
language: en
licence: CC BY 4.0
about: One stormy night on a rock in the sea.
start: shore
var: oil = 2
var: lamp = false

== shore
The waves are loud. The lighthouse is dark.
{lamp: Your lamp throws a small circle of light.|You can hardly see your hands.}
* Climb the stairs -> stairs
* {oil > 0 and not lamp} Light your lamp ~ lamp = true; oil -= 1 -> shore
* [once] Shout for help -> shout

== shout
Nobody answers but the gulls.
-> shore
```

## Header

Lines before the first passage, `key: value`. `title` is shown in the library; `author`,
`language`, `licence` and `about` (one line) on the story's first screen. `start` names the
first passage (default: the first one in the file). `var: name = value` declares a variable and
its starting value (a number, `true` / `false`, or a string in quotes). Lines starting with `//`
are comments, here and in passages.

## Passages

`== name` starts a passage. A name is letters, digits, `_` and `.`, starting with a letter or
`_`. The lines that follow, until the next `==`:

| line | meaning |
| --- | --- |
| text | shown as a paragraph; an empty line adds space |
| `* Label -> target` | a choice |
| `* {condition} Label -> target` | a choice shown only while the condition holds |
| `* Label ~ x = 1; y += 2 -> target` | a choice that changes variables when picked |
| `* [once] Label -> target` | a choice that disappears after it was picked once |
| `-> target` | no choices here: a **Continue** button to `target` |
| `-> {condition} target` | the same, used only when the condition holds (the first that holds wins) |
| `~ x = x + 1` | changes variables when the passage is shown |
| `~ {condition} x = 0` | the same, only when the condition holds |

A `->` is used only when the passage shows no choice at all: a passage that always shows a choice
never follows its `->`. To send the reader somewhere when a condition holds, give the check a
passage of its own with no text (`-> {oil == 0} empty` then `-> lamp`) and lead there.

`-> BACK` goes back to the page before, as **Undo** does (Twine's back links become this); a choice
leading back is shown only when there is a page to go back to.

A passage with no choices and no `->` is an ending. `-> END` ends the story too. If the passage
shows no text at all and has a `->` that holds, the app goes on at once (a silent redirect).

When a passage is shown: its visit count goes up by one, then its `~` lines run top to bottom,
then its text and choices are worked out.

## Text

- `{x}` prints a variable.
- `{condition: text}` shows the text only when the condition holds; `{condition: text|other}`
  shows `other` otherwise. These nest: `{lamp: The lamp {oil > 1: burns bright|flickers}.}`
- `{one|two|three}` shows `one` on the first visit to the passage, `two` on the second, then
  `three` from then on; `{&one|two}` cycles, `{~one|two}` picks at random.
- `\{`, `\}`, `\|`, `\\` are the characters themselves; `\*`, `\-`, `\~`, `\=` at the start of a
  line keep it a text line.

## Conditions and values

Numbers (whole), `true`, `false`, strings in `"…"`; variables; a passage name gives its visit
count (0 if never seen). Operators: `+ - * / %` (whole-number division), `== != < > <= >=`,
`and or not` (also `&& || !`), parentheses, and `random(a, b)`, `min(a, b)`, `max(a, b)`.
An undeclared name that is not a passage is 0. Assignments: `x = …`, `x += …`, `x -= …`,
several separated by `;`.

## Limits

A story up to a few megabytes works: the app reads one passage at a time. Keep a passage under
about 8,000 characters and a choice label under 200. The file name should end in `.story`; copy
it into `AppFiles/gamebook/` on the SD card.
