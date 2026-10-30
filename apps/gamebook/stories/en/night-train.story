title: The Night Train
author: omer-faruq
language: en
licence: CC BY 4.0
about: A necklace vanishes on the sleeper to the coast. You have until morning to find it. About fifteen minutes.
start: platform
var: clues = 0
var: gloves = false
var: ticket = false
var: whistle = false
var: hours = 0

== platform
The sleeper to the coast leaves at ten. You have a seat in the last carriage, a book you will not read, and no plans at all.
At half past eleven a woman screams in carriage three.
* Go and see -> scream

== scream
Mrs Ada Varga stands in the corridor in her dressing gown, pointing at an open jewel case. "My pearls," she says. "Someone took them while I was washing. Ten minutes, no more."
The conductor, a tired young man called Pim, looks at you. "You look like someone who reads detective stories. The police won't board until the coast. Would you help?"
* "Of course." -> corridor

== corridor
~ hours += 1
{hours >= 6: Grey light is coming up over the fields. The train will reach the coast soon.|The train rocks through the dark. It is {hours < 2: just after midnight|well past midnight}.}
You have found {clues} {clues == 1: clue|clues} so far.
Three other passengers have compartments in carriage three.
* {not gloves} Talk to Mr Holm, the salesman -> holm
* {not ticket} Talk to Miss Laine, the student -> laine
* {not whistle} Talk to the Count, who has not left his compartment -> count
* [once] Search the corridor and the washroom -> search
* {clues >= 2} Gather everyone and name the thief -> accuse
* {hours >= 6} Give up and wait for the police -> give_up

== holm
Mr Holm sells umbrellas and says so twice. He was asleep, he says, and heard nothing.
On his bunk lies a pair of white cotton gloves, the kind jewellers wear.
* "Are those yours?" -> holm_gloves
* Leave him be -> corridor

== holm_gloves
He goes red. "I clean my samples with them. Umbrellas have silver handles, you know." He shows you: they do.
You make a note anyway.
~ gloves = true
~ clues += 1
-> corridor

== laine
Miss Laine is reading a fat book about Roman law. She did hear something: a door, at about twenty past eleven, and quick footsteps going towards the back of the train.
Her ticket sticks out of the book as a bookmark.
* Look at the ticket -> laine_ticket
* Thank her and go -> corridor

== laine_ticket
It is a ticket to the coast, like yours. But it was bought this afternoon, for a train that left at nine. She is on the wrong train.
"I missed mine," she says calmly. "Pim let me on. Ask him."
~ ticket = true
~ clues += 1
-> corridor

== count
The Count opens his door a crack. He is fully dressed, coat and all, at midnight. "I am a light sleeper," he says. "I heard the woman scream. That is all."
* [once] Look past him into the compartment -> count_look
* Ask him why he is dressed -> count_dressed
* Leave -> corridor

== count_look
Behind him, on the little table, lies a silver whistle on a chain, the kind the train guards use.
"A souvenir," he says, and shuts the door.
~ whistle = true
~ clues += 1
-> corridor

== count_dressed
"I always dress before the coast. I like to be ready." He smiles without showing his teeth. "Good night."
-> corridor

== search
In the washroom, behind the pipe under the basin, your fingers find something small and hard: a single pearl, and a short piece of broken thread.
Whoever took the necklace came this way, towards the back of the train.
~ clues += 1
-> corridor

== accuse
Everyone squeezes into the corridor: Mrs Varga, Mr Holm, Miss Laine, the Count, and Pim with his lamp.
{clues >= 3: You go over what you know: the footsteps, the pearl behind the pipe, the guard's whistle.|You are not sure you know enough, but they are all looking at you.}
* Mr Holm, with his jeweller's gloves -> wrong_holm
* Miss Laine, on the wrong train -> wrong_laine
* The Count, dressed and ready to leave -> wrong_count
* {whistle} Pim, the conductor -> right

== wrong_holm
Mr Holm empties his case of umbrellas onto the floor, one by one, in silence. There are no pearls.
By the time he has packed them again, the train is at the coast and the police are on board. They never find the necklace.
-> END

== wrong_laine
Miss Laine closes her book. "I study law," she says. "Accusing someone without proof is a serious matter." She is right, and there is no necklace in her bag.
The police take everyone's name at the coast. The pearls are never seen again.
-> END

== wrong_count
The Count laughs. He turns out his pockets, opens his case and even takes off his shoes. Nothing.
"Ready to leave," he says, "because my daughter is waiting on the platform." She is. The pearls are not.
-> END

== right
"Pim," you say. "The footsteps went towards the back. Only the guard's van is back there. And the Count has a guard's whistle he says is a souvenir. Where did you lose yours?"
Pim's lamp shakes. The Count sighs. "He dropped it outside my door, running. I picked it up. I did not want to make trouble for a boy."
In the guard's van, under the coal for the stove, you find Mrs Varga's pearls, one short.
{clues >= 4: You give her the last pearl from your pocket, and she laughs out loud.|She counts them twice and says nothing about the missing one.}
-> END

== give_up
You sit in your compartment and watch the sun come up. At the coast the police search everyone's luggage for two hours.
Nobody finds the pearls. Some mornings you still wonder.
-> END
