title: Courier to Kepler Station
author: omer-faruq
language: en
licence: CC BY 4.0
about: One old cargo ship, three jumps and a crate you were told not to open. Every run is a little different. About fifteen minutes.
start: dock
var: fuel = 6
var: credits = 20
var: hull = 2
var: jump = 0
var: roll = 0
var: opened = false
var: passenger = false

== dock
The cargo bay of the Merry Widow smells of oil and burnt toast, and her hull still has a dent from the last run. The client, a thin woman in a grey coat, pays half in advance and pats the crate.
"Kepler Station, three jumps out. Don't open it. Don't scan it. Don't be late."
* "Of course." -> bridge
* [once] Ask what is inside -> ask

== ask
She smiles without warmth. "Something that pays well to deliver unopened." She leaves before you can ask anything else.
-> check

== check
-> {jump >= 3} arrival
-> {hull <= 0} wreck
-> {fuel < 2 and credits < 10} drifting
-> bridge

== bridge
{jump == 0: The bridge hums as the engines warm up.|Jump {jump} of 3 behind you.}
Fuel: {fuel}. Credits: {credits}. Hull: {hull} of 3.
{fuel < 2: Not enough fuel for another jump.}
* {fuel >= 2} Jump to the next system ~ fuel -= 2; jump += 1 -> event
* {credits >= 10 and fuel < 6} Buy fuel at the depot ~ credits -= 10; fuel += 3 -> refuel
* {credits >= 15 and hull < 3} Patch the hull ~ credits -= 15; hull += 1 -> repair
* {not opened} Open the crate -> crate

== refuel
The depot attendant fills your tanks and tells you three things about his cat you did not ask about.
-> check

== repair
A welder in a patched suit crawls over the hull for an hour. "She'll hold," she says. "Probably."
-> check

== crate
You stand in front of the crate for a long time.
* Open it ~ opened = true -> crate_open
* Leave it alone -> check

== crate_open
Inside, packed in straw, there is a small round robot with one sleepy blue eye. It looks at you and says: "Are we there yet?"
* "Not yet. Go back to sleep." -> check
* Let it sit on the bridge with you ~ passenger = true -> check

== event
~ roll = random(1, 6)
-> {roll <= 2} pirates
-> {roll <= 4} rocks
-> {roll == 5} distress
-> quiet

== quiet
{~The jump is quiet. You eat cold noodles and watch the stars smear and settle.|Nothing happens, and you are grateful for it.|A quiet jump. {passenger: The robot hums a tune it has made up.}}
-> check

== pirates
A rusty ship drops out of the dark right beside you and hails: "Cargo or credits, courier."
* {credits >= 10} Pay them off ~ credits -= 10 -> paid
* Run for it ~ fuel -= 1 -> run
* {passenger} Let the robot talk to them -> robot_talks

== paid
They take the credits and are gone before you can say anything rude.
-> check

== run
~ roll = random(1, 6)
{roll >= 4: You burn hard, and they cannot keep up.|A shot clips your hull before you get away.}
~ {roll < 4} hull -= 1
-> check

== robot_talks
The little robot rolls to the microphone and says, very politely, a string of numbers. The pirate ship goes silent. Then it turns and leaves at full speed.
"What did you tell them?" you ask. "Their mother's registration code," it says. "And where she is."
-> check

== rocks
An asteroid field, where the charts showed none.
* Fly through carefully ~ fuel -= 1 -> careful
* Fly through fast -> fast

== careful
Slow and patient, you thread the needle. It costs fuel, but nothing touches you.
-> check

== fast
~ roll = random(1, 6)
{roll >= 3: You whip through with a laugh you will be embarrassed about later.|A rock the size of a bus scrapes along the side.}
~ {roll < 3} hull -= 1
-> check

== distress
A distress beacon: a lifeboat, drifting, two miners inside.
* Pick them up ~ fuel -= 1; credits += 15 -> rescue
* Pass by -> pass_by

== rescue
They are cold and grateful and pay you everything in their pockets. "We'll remember the Merry Widow," says the older one.
-> check

== pass_by
You leave the beacon blinking behind you. It blinks in your head for the rest of the trip.
-> check

== drifting
The engines cough and stop. You drift, a long way from anywhere, until a slow tug answers your call three days later and tows you in, very late, for most of your fee.
-> END

== wreck
Alarms everywhere. You get into the escape pod with the crate, just in time, and watch the Merry Widow come apart behind you.
You deliver the crate a week late, in a pod. The client is not pleased.
-> END

== arrival
Kepler Station turns slowly against the stars. The woman in grey is waiting at the dock.
-> {opened and passenger} keep_robot
-> {opened} confess
-> delivered

== delivered
She checks the seal, nods once, and pays the rest. "On time and unopened. Rare." She hands you a card. "I'll have more work."
You never find out what was in the crate, and you decide you prefer it that way.
-> END

== confess
She sees the broken seal at once. "You opened it." The little robot's voice comes from inside: "Hello again!"
She sighs, then laughs. "It likes you. Fine. Half pay, and you never tell anyone."
-> END

== keep_robot
The robot will not get back in the crate. It hides under your console and says, "I want to stay with the courier."
The woman in grey looks at it for a long moment. "It was going to a museum," she says. "Perhaps it is better off flying." She pays you anyway, and leaves you a second crew member, one sleepy blue eye and all.
-> END
