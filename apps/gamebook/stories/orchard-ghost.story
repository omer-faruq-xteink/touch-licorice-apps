title: The Orchard Ghost
author: omer-faruq
language: en
licence: CC BY 4.0
about: A summer at your grandmother's farm, and a girl in the apple trees who should not be there. A gentle ghost story, about ten minutes.
start: arrive
var: ribbon = false
var: key = false
var: music = false
var: trust = 0

== arrive
Your grandmother's farm smells of hay and old wood. From the window of your room you can see the orchard, the apple trees in long crooked rows.
On your first night, in the moonlight, a girl in a white dress is standing between the trees, looking up at the house.
* Go down to the orchard -> orchard
* Pull the curtain shut and sleep -> morning

== morning
At breakfast your grandmother pours the tea. "You look tired," she says. "Did the orchard keep you awake? It does that to everyone in this family, sooner or later."
* [once] Ask her about the girl -> grandmother
* Go out and look around -> yard

== grandmother
Grandmother goes very still. "Her name was Elsie," she says at last. "My aunt. She was twelve. She lost something in the orchard the summer she died, and she never stopped looking." She pats your hand. "She won't hurt you. She's only sad."
~ trust += 1
-> yard

== yard
{yard == 1: The farmyard is bright and dusty. Chickens argue by the barn.|The farmyard again. The chickens have not stopped arguing.}
* {not ribbon} Search the barn -> barn
* {not key} Look in the old well -> well
* {not music} Climb up to the attic -> attic
* Wait for night in the orchard -> orchard

== barn
In the hay loft, caught on a nail, there is a faded blue ribbon, the kind a girl might wear in her hair a long time ago.
~ ribbon = true
-> yard

== well
The well is dry. On a ledge just below the rim, rusted almost shut, there is a small brass key.
~ key = true
-> yard

== attic
Under the roof, among old trunks, a little wooden box with a painted lid. It is locked.
* {key} Try the brass key -> music_box
* Leave it -> yard

== music_box
The key turns with a squeak. Inside, a tiny brass drum with pins, and when you open the lid wider, a tune plays: slow and a little out of tune, like someone humming in another room.
~ music = true
-> yard

== orchard
{orchard == 1: The grass is wet with dew. The girl is there, between the trees, closer than she looked from the window. She is pale, and you can see the moonlight through the edges of her dress.|The girl is waiting for you, as if she knew you would come.}
{trust >= 2: She smiles at you.}
* [once] Say hello -> hello
* {ribbon} Hold out the blue ribbon -> give_ribbon
* {music} Open the music box -> give_music
* {trust >= 3} Ask her what she lost -> lost
* Run back to the house -> run

== hello
"Hello," you say. Your voice sounds very loud.
"Hello," she says. Her voice sounds very far away. "Are you staying long?"
~ trust += 1
-> orchard

== give_ribbon
She takes the ribbon. It does not fall through her fingers, which surprises both of you. "I lost this in the hay," she says. "Mother was so cross." She ties it in her hair.
~ trust += 1
~ ribbon = false
-> orchard

== give_music
The tune drifts out over the grass. The girl closes her eyes and hums along, and for a moment she is not pale at all.
~ trust += 1
-> orchard

== lost
"My brother's song," she says. "He made the box for me. He played it every night, and when he went away to the war he said: keep it safe and I'll come back. I hid it, and I forgot where, and then I was ill, and then..." She looks at the house. "I've been looking ever since."
-> {music} found
* {not music} "I'll find it." -> promise

== promise
"Will you?" she says, and fades a little, like a breath on glass.
-> yard

== found
You hold out the box. You had it all along; she had heard it. She takes it in both hands and holds it against her chest.
"He did come back," she says. "Didn't he? He grew old here. I saw him sometimes, from the trees."
-> farewell

== farewell
The tune plays one last time. When it stops, the orchard is only an orchard, silver and quiet, and there is a blue ribbon on the grass where she stood.
In the morning your grandmother sees it in your hand and does not say anything at all. She only hugs you, for a long time.
-> END

== run
You run back through the wet grass and up the stairs and under the covers. Later, much later, you hear someone humming outside, very softly, until you fall asleep.
In the morning there is dew on the windowsill, and a single apple leaf.
-> END
