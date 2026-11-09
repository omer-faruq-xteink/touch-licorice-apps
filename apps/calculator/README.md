# Calculator — XTOS Licorice mini app (API 2.9)

A calculator with thumb-sized keys and the tools of a graphing calculator. The **Mode** button
(top right, named after the mode you are in) lists Basic, Sci and the other modes.

## Basic and Sci

- **Basic**: digits, + − × ÷, %, ±, Del, C. **Sci** adds sin cos
  tan and their inverses (in degrees or radians: Deg / Rad), ln and log, sqrt, x², x^y, n!, 1/x,
  pi, e, brackets and Ans.
- **2nd** swaps Sci's keys for a second page: 10^x, e^x, x³, ³sqrt, root(x, n), abs, int (rounds
  down), round(x, places), mod, nPr, nCr, gcd(a, b), lcm(a, b), rand, EE (×10^n), **Sto** (puts
  the result in a variable A–F), **Var** (puts a variable in the expression) and **Frac** (shows
  the result as a fraction: 0.75 = 3/4; tap again for the decimal). The comma separates a
  function's values.
- Type the expression as on paper: the usual precedence (powers, then × ÷ mod nPr nCr, then + −),
  brackets left open close at the end, "2 pi" and "3(4)" multiply. After = an operator goes on
  from the result.
- **Exact decimal arithmetic** (22 digits, shown to 16): 0.1 + 0.2 − 0.3 is 0 and 1 ÷ 3 × 3 is 1, as
  on a desk calculator. Square, cube and n-th roots are refined in decimal as well. Functions like
  sin or ln go through the reader's floating-point numbers; their result is shown to the digits
  those carry (measured at start) and marked "~".
- The last two results stay above the display (tap one to use its value); the mode, Deg / Rad,
  Ans, the variables and the last 20 results are kept between visits.
- Back on the calculator asks whether to leave; in a mode it goes back a screen.

## Modes

Each mode asks for numbers and functions on the calculator's own keys (with **Done** and
**Cancel** at the top), so every key works there; while you type a function of X, **X** takes
Ans's place.

- **Graph**: Y1–Y4, each on or off, drawn as a line, a thick line or dashes. **Window** (Xmin,
  Xmax, Xscl, Ymin, Ymax, Yscl), **Zoom** (Standard, Trig, In, Out, Square, Fit), **Trace** (< > one
  pixel, << >> fifteen, Next Y, or tap the plot), **Calc**: value at X, zero, minimum, maximum,
  intersection of two functions, dy/dx, and the integral between two values (shaded). Calc works
  from the formula (bisection, golden section, Simpson's rule), not from the pixels.
- **Table**: X from Start by Step, with every function that is on.
- **Stats**: lists L1 and L2 (200 values each). 1-Var: n, mean, sums, sample and population
  standard deviation, min, Q1, median, Q3, max (quartiles as on the TI-84). 2-Var: LinReg
  (a, b, r, r²), QuadReg (R²), ExpReg; **Plot** shows the points and the fit in Graph. Exact in
  decimal except ExpReg. Tap a result to keep it as Ans.
- **Distributions**: normalpdf, normalcdf, invNorm, tcdf, invT, chi²cdf, binompdf, binomcdf,
  poissonpdf, poissoncdf, geometpdf, geometcdf. Tails are computed as tails, so normalcdf(5, ∞)
  is 2.87e-7, not 1 − 0.9999997.
- **Solve**: Left = Right in X, every solution between From and To (a pole is not a solution; a
  curve that only touches zero is).
- **Matrix**: A, B, C up to 4 × 4; det, inverse, transpose, rref (solves a linear system written
  as an augmented matrix), +, −, × and k × A; exact in decimal; a result can be stored in A, B
  or C.
- **Units**: length, mass, temperature, area, volume, speed, time, data, energy, pressure and
  angle; a value is shown in every unit of its kind at once (exact factors: 1 in = 0.0254 m).
- **Base**: 32-bit whole numbers in hex, decimal, octal and binary at once; + − × ÷ mod, AND OR
  XOR NOT, << >>.
- **Finance**: TVM (N, I%, PV, PMT, FV, P/Y, End or Begin: fill four, Solve the fifth), the loan
  schedule with the total interest, and Percent (change from Old to New; a percentage added or
  taken off).
- **Dates**: two dates with weekday, day of the year and ISO week; the days between them (also
  in weeks, and in years, months and days); a date plus or minus N days.

## Speed

Basic and Sci run the same code whether the modes exist or not: each mode is a file of its own
(`modes/*.lua`, packed next to `index.lua`) that is loaded with `require` the first time it is
opened, and its saved data (`graph.txt`, `stats.txt`, ...) is read only then. A tap draws one
frame (the finger going down draws nothing), so a key answers in one e-ink refresh.

Files: `src/decimal.lua` (the decimal numbers) and `src/main.lua` (on `tools/gamekit`), bundled
into `index.lua` by `bundle.py`; `modes/ui.lua` (shared screen pieces), `modes/fexpr.lua`
(functions of X compiled to floats for Graph, Table and Solve) and one file a mode;
`test_calculator.py` (Basic and Sci, against Python's Decimal) and `test_modes.py` (every mode,
against Python's math, statistics, fractions and datetime): `python -I apps/calculator/test_calculator.py`.
