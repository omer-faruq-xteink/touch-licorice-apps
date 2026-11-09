-- a small module: returns a table, counts how often its body ran
RUNS = (RUNS or 0) + 1
return { answer = 42, runs = RUNS }
