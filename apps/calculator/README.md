# Calculator — XTOS Licorice mini app (API 2.9)

A calculator with thumb-sized keys.

- **Basic**: digits, + − × ÷, %, ±, Del, C. **Sci** (the button at the top right) adds sin cos
  tan and their inverses (in degrees or radians: Deg / Rad), ln and log, sqrt, x², x^y, n!, 1/x,
  pi, e, brackets, EE (×10^n) and Ans.
- Type the expression as on paper: the usual precedence (powers, then × ÷, then + −), brackets left
  open close at the end, "2 pi" and "3(4)" multiply. After = an operator goes on from the result.
- **Exact decimal arithmetic** (22 digits, shown to 16): 0.1 + 0.2 − 0.3 is 0 and 1 ÷ 3 × 3 is 1, as
  on a desk calculator. Square roots are refined in decimal as well. Functions like sin or ln go
  through the reader's floating-point numbers; their result is shown to the digits those carry
  (measured at start) and marked "~".
- The last two results stay above the display (tap one to use its value); the mode, Deg / Rad,
  Ans and the last 20 results are kept between visits.

Files: `src/decimal.lua` (the decimal numbers), `src/main.lua` (on `tools/gamekit`), `bundle.py`,
`test_calculator.py` (`python -I apps/calculator/test_calculator.py`, which checks the decimal
numbers against Python's).
