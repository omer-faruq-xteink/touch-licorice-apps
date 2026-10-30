# title: Ink Test
# author: Tester
VAR coins = 2
VAR met = false

Once upon a time.
-> village

=== village ===
You are in the village. {coins > 0: You have {coins} coins.|You are broke.}
{&The bell rings.|A dog barks.}
* [Talk to the smith]
    "Hello," says the smith.
    ~ met = true
    ** [Ask about swords] "Too dear," she says.
    ** (haggle) [Haggle]
        ~ coins = coins - 1
        You haggle. <>
        It works.
    -- You leave the forge.
* {coins >= 2} [Buy bread] You buy bread.
    ~ coins -= 2
+ [Wait] Time passes.
    -> village
* -> forest
- Back in the square.
-> forest

=== forest ===
{ met:
    The smith's words ring in your ears.
- else:
    You know nobody here.
}
{village.haggle: You haggled once.}
+ [Go home] -> home
+ [Go back] -> village

=== home ===
= door
You reach the door.
-> END
