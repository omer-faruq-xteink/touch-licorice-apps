title: The Mountain Hut
author: omer-faruq
language: en
licence: CC BY 4.0
about: Snow, a hut, one night and a long way down. Every game is a little different. About ten minutes.
start: storm
var: warmth = 3
var: wood = 0
var: food = 1
var: day = 1
var: weather = 0
var: map = false

== storm
The snow came faster than the forecast said. By four o'clock you cannot see your own ski tips.
Then, out of the white, a dark square: a hut.
* Stumble inside -> hut

== hut
~ warmth = max(warmth, 0)
{warmth >= 3: You are warm enough.|{warmth > 0: You are cold.|You are shaking with cold and cannot stop.}}
{day == 1: It is the first night.|It is night {day}.} Wood by the stove: {wood}. Food left: {food}.
* {wood > 0} Light the stove ~ wood -= 1; warmth += 2 -> fire
* [once] Search the hut -> search
* Go out for wood ~ warmth -= 1 -> woodpile
* {food > 0} Eat ~ food -= 1; warmth += 1 -> eat
* Sleep until morning -> night

== search
A tin of biscuits on the shelf, and pinned to the wall a hand-drawn map of the valley, with the safe way down marked in red pencil.
~ food += 2
~ map = true
-> hut

== woodpile
~ weather = random(1, 6)
{weather <= 2: The wind knocks you flat twice before you find the woodpile. You come back with two logs and no feeling in your fingers.|You dig the woodpile out of the snow and come back with an armful.}
~ wood += 3
~ {weather <= 2} wood -= 1
~ {weather <= 2} warmth -= 1
-> hut

== fire
The stove ticks and roars. Steam rises from your gloves on the rail.
-> hut

== eat
Biscuits, slightly soft. The best meal of your life.
-> hut

== night
~ warmth -= 2
~ weather = random(1, 6)
{warmth > 0: You sleep badly, but you sleep.|You lie awake all night, too cold to sleep.}
-> {warmth <= -2} frozen
-> morning

== morning
~ day += 1
{weather >= 4: The morning is clear and still. The whole valley shines below you.|The snow is still falling, softer now. You can see perhaps fifty metres.}
* {weather >= 4} Ski down now -> descent
* {weather < 4 and map} Ski down by the map -> descent_map
* {weather < 4} Ski down anyway -> lost
* {day < 4} Stay another day -> hut
* {day >= 4} Stay another day -> rescue

== descent
You take the long, gentle slopes one by one. By noon you see the village roofs, and by one o'clock you are drinking hot chocolate in the café as if nothing happened.
-> END

== descent_map
The red pencil line takes you down a gully you would never have found, out of the wind. In the trees the snow stops, and the village is below you.
-> END

== lost
In the white everything looks the same. You ski for an hour and find your own tracks. Then you find the hut again, which is luck of a kind.
~ warmth -= 1
-> hut

== rescue
On the fourth day you hear it before you see it: a helicopter, low over the ridge. Someone at the café noticed your car was still in the car park.
The pilot shakes your hand. "Good choice, staying put," she says.
-> END

== frozen
Some time before dawn you stop feeling the cold, which is the worst sign there is. The rescue team that finds you two days later says you were lucky to live.
Next time, keep the stove going.
-> END
