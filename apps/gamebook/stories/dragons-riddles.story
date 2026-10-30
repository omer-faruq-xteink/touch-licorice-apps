title: The Dragon's Riddles
author: omer-faruq
language: en
licence: CC BY 4.0
about: The only road over the mountains runs through a dragon's cave. She will let you pass if you can answer her riddles. About ten minutes.
start: road
var: right = 0
var: wrong = 0
var: hint = false
var: gift = false

== road
The pass is narrow, and the snow on either side is deeper than you are tall. Where the road should go on, it goes into a cave.
Inside, something enormous breathes out, and warm air rolls over you like a summer wind.
* Walk in -> cave
* [once] Look for another way -> no_way

== no_way
You climb for an hour. There is no other way: only cliffs, and an eagle who looks at you as if you were lunch.
-> road

== cave
A dragon lies coiled around a heap of things that glitter, one golden eye open and fixed on you.
"A traveller," she says, in a voice like stones rolling. "Few come this way. Fewer go on. I will let you pass if you answer three riddles. If you cannot, you may go back the way you came, and that is all."
* "And if I refuse?" -> refuse
* [once] Offer her the apple in your pocket ~ gift = true -> apple
* "I'm ready." -> riddle1

== refuse
"Then you may sit in the snow until spring." She closes her eye. The cave grows a little colder.
-> cave

== apple
She sniffs it, then takes it from your palm very delicately between two teeth the size of your arm. "No one has brought me anything in three hundred years," she says. "I shall remember it."
~ hint = true
-> cave

== riddle1
"The first. I have a mouth but never eat, a bed but never sleep, I run but have no feet. What am I?"
* "A river." ~ right += 1 -> riddle1_yes
* "A clock." ~ wrong += 1 -> riddle1_no
* "A road." ~ wrong += 1 -> riddle1_no

== riddle1_yes
"A river," she agrees, and something like a smile shows between her teeth.
-> riddle2

== riddle1_no
"No," she says, not unkindly. "A river. It has a mouth, a bed, and it runs. Still, there are two more."
-> riddle2

== riddle2
"The second. The more of me you take, the more you leave behind. What am I?"
{hint: She taps the stone floor with one claw, very slowly, one step after another.}
* "Footsteps." ~ right += 1 -> riddle2_yes
* "Memories." ~ wrong += 1 -> riddle2_no
* "Breath." ~ wrong += 1 -> riddle2_no

== riddle2_yes
"Footsteps. Yes." Her tail shifts, and a waterfall of coins slides down the heap.
-> riddle3

== riddle2_no
"Footsteps," she says. "You left a trail of them all the way up the mountain."
-> riddle3

== riddle3
"The last, and the hardest. What can fill a room but takes up no space?"
{hint: Her eye glows a little brighter, lighting up the dark corners of the cave.}
* "Light." ~ right += 1 -> riddle3_yes
* "Air." ~ wrong += 1 -> riddle3_no
* "Silence." ~ wrong += 1 -> riddle3_no
* [once] "May I think about it?" -> think

== think
"Think," she says. "I have time. You, I suspect, have less." You sit on a cold rock. Her eye glows in the dark like a lamp.
-> riddle3

== riddle3_yes
"Light," she says softly. "Light, which I have not seen in a long time, down here."
-> judge

== riddle3_no
"Light," she says. "Even mine, a little, though I keep it shut away."
-> judge

== judge
-> {right == 3} all_three
-> {right == 2} two
-> {right < 2 and gift} kind
-> failed

== all_three
"Three of three." The dragon uncoils, and the cave is bigger than you thought: at its far end there is daylight. "Go on, riddler. And take something from the heap. Anything."
You take a silver compass that points, the dragon says, to whatever you are looking for. You never get lost again.
-> END

== two
"Two of three. That is enough." She moves her tail aside, and you walk past her towards the daylight at the back of the cave.
"Come back when you know more riddles," she calls after you. "I get bored."
-> END

== kind
"One, or none," she says. "By the rules you should go back." She looks at the place where the apple was. "But rules are for those who bring nothing. Go on."
You walk past her into the light, and you are the first traveller in three hundred years to pass without the answers.
-> END

== failed
"Not enough," the dragon says, and closes her eye. "Go home, traveller. Learn some riddles. The mountain will still be here."
You walk back down through the snow. It is a long way round, by the coast road, but you get there in the end.
-> END
