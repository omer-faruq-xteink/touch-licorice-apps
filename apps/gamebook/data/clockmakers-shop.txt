title: The Clockmaker's Shop
author: omer-faruq
language: en
licence: CC BY 4.0
about: Your grandfather left you a shop full of clocks and one locked door. A puzzle story, about fifteen minutes.
start: door
var: wound = 0
var: hall = false
var: cuckoo = false
var: carriage = false
var: note1 = false
var: note2 = false
var: note3 = false
var: tries = 0

== door
The shop has been closed for a year. The key the lawyer gave you is heavier than it looks, and the bell above the door still rings when you open it.
Inside, on every wall and shelf, clocks. All of them have stopped.
At the back there is a small door with a brass lock that has three dials, each from 1 to 12.
* Look around the shop -> shop

== shop
{shop == 1: Dust lies on everything except a workbench, which someone kept clean to the end.|The shop is quiet{wound > 0: except for the ticking of {wound} {wound == 1: clock|clocks}}.}
* {not hall} Wind the tall hall clock -> hall_clock
* {not cuckoo} Wind the cuckoo clock -> cuckoo_clock
* {not carriage} Wind the little carriage clock -> carriage_clock
* [once] Look at the workbench -> bench
* Try the lock on the back door -> lock

== bench
Tools in their places, a magnifying glass, and a card in your grandfather's handwriting:
"Every clock tells the time. Mine tell a secret too. Wake them, and listen."
-> shop

== hall_clock
You open the long case and wind the weights up. The pendulum swings. After a moment the clock strikes, slowly, and stops at the same hour every time you try it.
{&Bong.|Bong. Bong.|It is a deep, patient sound.}
You count the strokes: seven.
~ hall = true
~ note1 = true
~ wound += 1
-> shop

== cuckoo_clock
The cuckoo clock needs a little oil and a gentle push. Then the doors fly open and the bird comes out, and out, and out again.
Three calls, and it goes back inside and refuses to come out again.
~ cuckoo = true
~ note2 = true
~ wound += 1
-> shop

== carriage_clock
The carriage clock winds with a tiny key hanging from its handle. When it starts, its hands spin by themselves and stop at a quarter past something.
The hour hand points straight at the eleven.
~ carriage = true
~ note3 = true
~ wound += 1
-> shop

== lock
~ tries += 1
The three dials are stiff with age.
{wound == 0: You have no idea what numbers to try.}
{wound > 0 and wound < 3: Some of the clocks are talking to you. Not all of them yet.}
{tries >= 4 and wound < 3: You are guessing now, and you know it.}
* {note1 and note2 and note3} Set the dials to 7, 3, 11 -> opened
* {note1 and note2 and note3} Set the dials to 11, 3, 7 -> wrong
* Turn the dials at random -> wrong
* Leave the lock alone -> shop

== wrong
The lock does not move. Somewhere in the shop a clock ticks, as if it were laughing at you.
{tries >= 3: Maybe you should listen to the clocks in the order you woke them... or in the order they stand from the door.}
-> shop

== opened
The lock gives a small click, the same sound a clock makes when it is wound just right.
Behind the door is a tiny room with a window onto the garden, and on the table a clock you have never seen: a plain wooden one, with a photograph of you as a child glued inside its lid.
* Wind it -> last_clock

== last_clock
It starts at once. There is a folded letter under it.
"I knew you would get here. You always took things apart to see how they worked. The shop is yours, if you want it. If you don't, sell the clocks, but keep this one. Love, Grandad."
The clocks in the shop strike together, all of them, for the first time in a year.
-> END
