"""Offline test of the Calculator (gamekit harness): the decimal module against Python's Decimal,
exact results (0.1 + 0.2 - 0.3, 1/3 * 3), precedence, brackets, implicit multiplication, the
scientific functions in degrees and radians, square roots refined in decimal, n!, errors, Ans,
the history, the modes and the draw-command count.

  python -I apps/calculator/test_calculator.py
"""
import os, random, sys
from decimal import Decimal, getcontext
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(HERE)), 'tools', 'gamekit'))
from harness import Game  # noqa: E402

getcontext().prec = 60
g = Game(HERE)
A = lambda: g.api
D = A().D

# the decimal module: + - * / against Python's Decimal, to 20 significant digits
rng = random.Random(5)


def rnd():
    digits = rng.randint(1, 18)
    s = str(rng.randint(1, 10 ** digits))
    e = rng.randint(-12, 12)
    return ('-' if rng.random() < 0.4 else '') + s + 'e' + str(e)


for _ in range(500):
    a, b = rnd(), rnd()
    da, db = D.parse(a), D.parse(b)
    pa, pb = Decimal(a), Decimal(b)
    for name, op, want in (('add', D.add, pa + pb), ('sub', D.sub, pa - pb), ('mul', D.mul, pa * pb), ('div', D.div, pa / pb)):
        got = Decimal(str(D.format(op(da, db), 22)))
        if want == 0:
            assert got == 0, (name, a, b, got)
        else:
            assert abs((got - want) / want) < Decimal('1e-20'), (name, a, b, got, want)
assert D.format(D.parse('0.1'), 16) == '0.1' and D.format(D.parse('123e-8'), 16) == '0.00000123'
assert D.format(D.parse('1e25'), 16) == '1e+25' and D.format(D.parse('-2.50'), 16) == '-2.5'


def keys(*labels):
    for l in labels:
        g.tap_label(l)


def mode(name):
    g.tap(480 - 60, 30)                     # the Mode button, then a name in its list
    g.tap_label(name)


def run(*labels):
    keys('C', *labels, '=')
    return str(A().result()) if A().result() else None


# exact decimal arithmetic
assert run('0', '.', '1', '+', '0', '.', '2', '-', '0', '.', '3') == '0'
assert run('1', '÷', '3', '×', '3') == '1'
assert run('2', '+', '3', '×', '4') == '14'
assert run('9', '9', '9', '9', '9', '9', '9', '9', '9', '9', '9', '×', '9', '9', '9', '9', '9', '9', '9', '9', '9', '9', '9') == '9.9999999998e+21'
assert run('5', '0', '%') == '0.5'
assert run('7', '±', '×', '2') == '-14'
t = g.texts()
assert '= -14' in t and any('7' in s and '×' in s for s in t), t
# division by zero: an error, not a crash
assert run('1', '÷', '0') is None and str(A().err()) == 'division by zero'
assert 'Error: division by zero' in g.texts()
# backspace and going on from the answer
keys('C', '1', '2', '3', 'Del', '=')
assert str(A().result()) == '12'
keys('+', '1', '=')
assert str(A().result()) == '13' and 'Ans + 1' in A().expr()

# the scientific mode
assert 'Basic' in g.texts()                # the button is named after the mode
mode('Sci')
assert str(A().mode()) == 'sci' and 'sin' in g.texts() and 'Sci' in g.texts()
assert run('(', '2', '+', '3', ')', '×', '4') == '20'
assert run('2', 'pi') == '6.283185307179586'
assert run('sqrt', '2') == '1.414213562373095'               # refined in decimal: no "~"
assert run('sqrt', '1', '6', '9') == '13'
assert run('1', '0', 'n!') == '3628800'
assert run('2', 'x^y', '1', '0') == '1024'
assert run('2', 'x^y', '0', '.', '5').startswith('1.41421356237') and '~' in ' '.join(g.texts())
assert run('3', 'x²') == '9' and run('4', '1/x') == '0.25'
assert run('sin', '3', '0') == '0.5' and run('cos', '9', '0') == '0' and run('tan', '4', '5') == '1'
assert run('asin', '1') == '90'
assert run('ln', 'e') == '1' and run('log', '1', '0', '0', '0') == '3'
g.tap_label('2nd')
assert run('1', 'EE', '3', '+', '1') == '1001'
g.tap_label('2nd')
assert run('-', '2', 'x^y', '2') == '-4'
assert run('sin', '9', '0', ')', '+', '1') == '2'
g.tap_label('Deg')                                          # radians
assert 'Rad' in g.texts()
assert run('sin', 'pi', '÷', '2') == '1'
assert run('sqrt', '-', '4') is None and 'square root' in str(A().err())
assert run('ln', '0') is None and run('tan', '4', '5') is not None
g.tap_label('Rad')

# history: the last results stay; a tap uses one
h = list(A().history().values())
assert len(h) >= 10 and str(h[-1][2]).startswith('~1.6197')  # tan(45) in radians, the last one worked out
keys('C')
g.tap(30, 34 + 4)                                           # the newer of the two lines
assert A().expr() != ''
# kept between visits
g.restart()
assert str(A().mode()) == 'sci' and len(list(A().history().values())) == len(h)

# the draw commands stay well under the reader's limit
assert g.commands() < 300, g.commands()
mode('Basic')
assert str(A().mode()) == 'basic' and 'sin' not in g.texts()

# Sci's 2nd page
mode('Sci')
g.tap_label('2nd')
assert '10^x' in g.texts() and 'sin' not in g.texts()
assert run('10^x', '3') == '1000'
assert run('³sqrt', '2', '7') == '3' and run('³sqrt', '-', '8') == '-2'
assert run('root', '8', '1', ',', '4') == '3'
assert run('2', 'x³') == '8'
assert run('abs', '-', '5') == '5'
assert run('int', '-', '2', '.', '5') == '-3'
assert run('round', '2', '.', '3', '4', '5', ',', '2') == '2.35' and run('round', '2', '.', '5') == '3'
assert run('1', '7', 'mod', '5') == '2' and run('-', '7', 'mod', '3') == '2'
assert run('5', 'nCr', '2') == '10' and run('5', 'nPr', '2') == '20' and run('5', '2', 'nCr', '5') == '2598960'
assert run('gcd', '1', '2', ',', '1', '8') == '6' and run('lcm', '4', ',', '6') == '12'
assert run('e^x', '0') == '1'
assert run('gcd', '1', '2') is None and 'comma' in str(A().err())
# Frac: 0.75 -> 3/4, 1/3 -> 1/3 (exact decimals, continued fractions)
keys('C', '0', '.', '7', '5', '=', 'Frac')
assert str(A().frac()) == '3/4' and '= 3/4' in g.texts()
keys('Frac')
assert A().frac() is None
keys('C', '1', '÷', '3', 'Frac')
assert str(A().frac()) == '1/3'
keys('C', '2', 'Frac')
assert str(A().frac()) == 'no simple fraction'
# variables: Sto puts the result in A-F, Var puts a letter in the expression
keys('C', '4', '2', 'Sto')
g.tap_label('B')
assert A().var('B') == '42'
keys('C', 'Var')
g.tap_label('B')
keys('×', '2', '=')
assert str(A().result()) == '84'
g.tap_label('2nd')
g.restart()
assert A().var('B') == '42'

# Back: the host's question on the calculator itself (not handled), one frame per tap
back = g.L.eval("function() return on_input(ctx, {type='key', key='back', phase='up'}) end")
assert back() is False
g.L.execute("frames = 0; ctx.invalidate = function() frames = frames + 1 end")
keys('7')
assert int(g.g.frames) == 1, int(g.g.frames)                 # down + up: one frame, for the up

# Basic and Sci never load a mode's file
assert int(A().loaded()) == 0
assert g.L.eval("package.loaded['modes.ui'] == nil and package.loaded['modes.graph'] == nil")
print('float digits here:', int(A().FLOAT_DIGITS))
g.no_err()
print('calculator tests passed')
