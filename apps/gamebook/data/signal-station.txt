title: Signal from Station Nine
author: omer-faruq
language: en
licence: CC BY 4.0
about: A research station on the ice, a dead radio and a strange signal. Keep the power up and find out who is calling. About fifteen minutes.
start: wake
var: power = 5
var: heat = true
var: radio = false
var: decoded = false
var: fuel = 1
var: shift = 0

== wake
The alarm wakes you at three in the morning. Not the fire alarm: the soft one, the one that means the power is low.
You are alone on Station Nine. The others flew out before the storm. The relief plane comes in four days.
Through the window, the ice is blue in the moonlight. On the console, a light you have never seen blink before is blinking.
* Get up -> hub

== hub
~ shift += 1
~ {heat} power -= 1
~ power = max(power, 0)
-> {power == 0 and heat} dark
-> station

== station
Power: {power} of 10. Heating: {heat: on|off}. Spare fuel cans: {fuel}.
{power <= 2 and heat: The lights flicker. The heating is eating the last of the power.}
{not heat: Your breath smokes in the air.}
* {fuel > 0} Refuel the generator ~ fuel -= 1; power += 4 -> generator
* {heat} Turn the heating off to save power ~ heat = false -> hub
* {not heat} Turn the heating back on ~ heat = true -> hub
* [once] Go out to the fuel store -> store
* {not radio} Fix the radio -> radio_room
* {radio and not decoded} Listen to the signal -> signal
* {decoded} Answer the signal -> answer
* {shift >= 8} Wait for the plane -> plane

== generator
The generator coughs, catches and settles into its low hum. The lights come up to full.
-> hub

== store
~ shift += 1
Twenty metres to the fuel store, holding the guide rope. The wind {~takes your hat|fills your hood with snow|knocks you to your knees once}.
Inside you find {shift < 4: three cans|two cans; the rest have frozen solid}.
~ {shift < 4} fuel += 3
~ {shift >= 4} fuel += 2
-> hub

== radio_room
The radio's power board has a burnt fuse. There is a box of spares somewhere.
* [once] Search the drawers -> fuse
* Go back -> hub

== fuse
Under a pile of old weather logs: one fuse, the right size. You put it in and the radio hisses into life.
~ radio = true
~ power -= 1
-> hub

== signal
Through the hiss, a pattern of beeps: short, short, short, long, long, long, short, short, short. Again and again.
* Write it down -> morse
* Turn it off and go back to bed -> bed

== morse
You know this one. Everybody knows this one. S O S.
And under it, faint, a position: forty kilometres east, out on the sea ice.
~ decoded = true
-> hub

== bed
You lie awake listening to the wind. The pattern goes round and round in your head until you get up again.
-> hub

== answer
You key the microphone. "Station Nine. I hear you. Who is this?"
A pause, and then a voice, thin and shaking: two scientists, their tracked vehicle broken down on the ice, their heater failing.
* {power >= 3} Relay their position to the coast guard -> relay
* {power < 3} Try to reach the coast guard -> weak
* Tell them to hold on and that help is coming -> comfort

== relay
The long-range radio drinks power, but the coast guard answers on the second call. A helicopter will fly at first light.
You stay on the radio with the two on the ice for the rest of the night, talking about anything at all.
-> rescued

== weak
The radio needs more power than you have. The coast guard's answer is broken up by static.
* {fuel > 0} Refuel first ~ fuel -= 1; power += 4 -> answer
* Keep trying anyway -> lost_contact

== comfort
"Help is coming," you say, and you mean it. Then you go to find the power to make it true.
-> hub

== rescued
At dawn you watch the helicopter go out over the ice, and an hour later come back with two more people than it left with.
When the relief plane lands three days later, the pilot finds you asleep in the radio room with the headphones still on.
-> END

== lost_contact
The static swallows everything. In the morning the coast guard finds the vehicle from the air, following the tracks. The two scientists are alive, just.
"We heard you," one of them says later. "That helped."
-> END

== dark
The last light goes out. The heating stops. In the dark you find the fuel cans by touch, but your fingers are too cold to open them.
You spend the night wrapped in every sleeping bag on the station. In the morning you are alive, and the radio has been silent for hours.
-> END

== plane
The storm blows itself out. On the fourth day the relief plane drops out of a clear sky.
{decoded: You tell the pilot about the signal. They fly east at once, but find only an empty vehicle and footprints leading away.|Nothing much happened, you tell them. You never did find out what that blinking light meant.}
-> END
