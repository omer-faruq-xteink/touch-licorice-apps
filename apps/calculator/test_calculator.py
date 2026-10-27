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
g.tap_label('Sci')
assert str(A().mode()) == 'sci' and 'sin' in g.texts() and 'Basic' in g.texts()
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
assert run('1', 'EE', '3', '+', '1') == '1001'
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
g.tap_label('Basic')
assert str(A().mode()) == 'basic' and 'sin' not in g.texts()
print('float digits here:', int(A().FLOAT_DIGITS))
g.no_err()
print('calculator tests passed')
