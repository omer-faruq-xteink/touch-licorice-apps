title: The Midnight Market
author: omer-faruq
language: en
licence: CC BY 4.0
about: Once a year a market opens where you pay with memories. Buy wisely. A fairy tale, about ten minutes.
start: gate
var: memories = 3
var: lantern = false
var: compass = false
var: song = false
var: gave_birthday = false
var: gave_summer = false
var: gave_first = false

== gate
At midnight, in the alley behind the bakery, a gate stands where there was only a wall this afternoon.
A small man in a green coat bows. "Welcome to the Midnight Market. We take no money here. You pay with memories, and you have three good ones to spend."
* Step through -> square

== square
{square == 1: Stalls lit with candles fill a square that cannot possibly fit behind the bakery. Everyone is whispering.|The square hums with whispers.}
You have {memories} {memories == 1: memory|memories} left to spend.
* {not lantern} Visit the lantern seller -> lanterns
* {not compass} Visit the map maker -> maps
* {not song} Visit the woman who sells songs -> songs
* [once] Ask the man in green how to get home -> ask
* Leave the market -> leave

== ask
"The same way you came," he says, "if you can find it. The gate moves. Some people buy something to help them. Some people stay."
He smiles in a way you do not like.
-> square

== lanterns
A lantern that never goes out, and shows only what is real.
"One memory," says the seller. "Which will you give?"
* {not gave_birthday} Your tenth birthday ~ gave_birthday = true; memories -= 1; lantern = true -> bought
* {not gave_summer} The summer at the lake ~ gave_summer = true; memories -= 1; lantern = true -> bought
* {not gave_first} The day you learned to ride a bike ~ gave_first = true; memories -= 1; lantern = true -> bought
* Not today -> square

== maps
A brass compass whose needle points to the place you most want to be.
"One memory," says the map maker.
* {not gave_birthday} Your tenth birthday ~ gave_birthday = true; memories -= 1; compass = true -> bought
* {not gave_summer} The summer at the lake ~ gave_summer = true; memories -= 1; compass = true -> bought
* {not gave_first} The day you learned to ride a bike ~ gave_first = true; memories -= 1; compass = true -> bought
* Not today -> square

== songs
A song that makes anyone who hears it remember something good.
"One memory," she says, "though you could keep yours and just listen for free."
* [once] Listen for free -> listen
* {not gave_birthday} Your tenth birthday ~ gave_birthday = true; memories -= 1; song = true -> bought
* {not gave_summer} The summer at the lake ~ gave_summer = true; memories -= 1; song = true -> bought
* {not gave_first} The day you learned to ride a bike ~ gave_first = true; memories -= 1; song = true -> bought
* Not today -> square

== listen
She hums a few notes, and for a moment you smell cut grass and hear someone laughing. Then it is gone.
"That is all you get for free," she says kindly.
-> square

== bought
The seller touches your forehead with one cold finger. Something small and bright goes out of you, like a candle you did not know was burning.
{memories == 0: You feel lighter. Too light. You try to remember why you came here and cannot quite.}
-> square

== leave
The man in green appears at your elbow. "Leaving already? The gate is somewhere. Good luck."
The stalls all look the same. The alleys all bend back to the square.
{memories == 0: You hold the things you bought and cannot think what they are for.}
-> {memories == 0} stay
* {memories > 0 and compass} Follow the compass -> compass_way
* {memories > 0 and lantern} Hold up the lantern -> lantern_way
* {memories > 0 and song} Sing the song you bought -> song_way
* {memories > 0} Walk and hope -> wander

== compass_way
The needle swings once and points, steady as a finger, down an alley you had not noticed. At the end of it: the wall behind the bakery, with a door-shaped gap in it.
-> home

== lantern_way
In the lantern's light the market looks different: the stalls are cardboard, the candles are painted, and the gate stands right behind you, where it always was.
-> home

== song_way
You sing, and the people around you stop and smile and remember something. The man in green remembers something too, and while he stands there with wet eyes, you walk past him and out through the gate.
-> home

== wander
You walk for what feels like hours. Then, by luck or by kindness, you find a crack of grey morning between two stalls and squeeze through it.
-> home

== home
You are standing in the alley behind the bakery. It is dawn, and the baker is putting out the first loaves.
{memories == 3: You kept all your memories. They feel heavier than before, and warmer.|{memories == 2: You gave away one memory. You will never know which one you miss.|You gave away {3 - memories} memories. Some mornings you will feel a space where something used to be.}}
-> END

== stay
You stop looking for the gate. The market is warm, and someone offers you a stall of your own. You cannot remember a reason to say no.
Somewhere, a bakery opens without you.
-> END
