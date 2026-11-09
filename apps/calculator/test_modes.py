"""Offline test of the Calculator's other modes (modes/*.lua) in the gamekit harness: each is
opened from Modes and driven with taps; the numbers are checked against Python (math,
statistics, fractions, datetime). Also: a mode's file is loaded only when it is opened, the
calculator keys work inside a mode's questions, and every screen stays under the reader's 1024
draw commands.

  python -I apps/calculator/test_modes.py
"""
import datetime, math, os, statistics, sys
from fractions import Fraction
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(HERE)), 'tools', 'gamekit'))
from harness import Game  # noqa: E402

g = Game(HERE)
# the package's own require: modes/<name>.lua next to index.lua
g.L.execute(f"package.path = [[{HERE.replace(os.sep, '/')}/?.lua;]] .. package.path")
A = lambda: g.api


def keys(*labels):
    for l in labels:
        g.tap_label(l)


def typed(*labels):
    """type on the calculator keys while a mode asks, then Done"""
    assert A().editing(), 'not asking'
    keys(*labels, 'Done')


def open_mode(name):
    g.tap(480 - 60, 30)                    # the Mode button
    g.tap_label(name)
    assert str(A().screen()) == name, A().screen()


def T(name):
    return A().mod(name).test


def near(a, b, rel=1e-6):
    return abs(float(a) - float(b)) <= rel * max(1.0, abs(float(b)))


def under_limit():
    n = g.commands()
    assert n < 1024, n
    return n


def back():
    return g.L.eval("on_input(ctx, {type='key', key='back', phase='up'})")


def loaded(name):
    return g.L.eval(f"package.loaded['modes.{name}'] ~= nil")


# nothing is loaded until a mode is opened
assert int(A().loaded()) == 0 and not loaded('ui')

# ---------------------------------------------------------------- Graph
open_mode('Graph')
assert loaded('graph') and loaded('ui') and loaded('fexpr') and not loaded('stats')
keys('Y=')
g.tap(100, 80)                                             # Y1's line
assert A().editing() and 'X' in g.texts()                  # X takes Ans's place
typed('X', 'x²', '-', '4')
g.tap(150, 70 + 112 + 10)                                  # Y2
typed('X')
assert 'Y1 = X² - 4' in g.texts(), g.texts()
keys('Graph')
G = T('graph')
assert near(G.fns[1](3), 5) and near(G.fns[2](7), 7)
assert len(list(G.curves()[1].values())) >= 1
n = under_limit()
# Calc, from the trace point near 1.5
G.trace.x = 1.5
keys('Calc', 'Zero')
assert near(G.trace.x, 2, 1e-5), G.trace.x
keys('Calc', 'Minimum')
assert near(G.trace.x, 0, 1e-4) or abs(G.trace.x) < 1e-4, G.trace.x
G.trace.x = 2.4
keys('Calc', 'Intersect')
assert near(G.trace.x, (1 + math.sqrt(17)) / 2, 1e-5), G.trace.x
G.trace.x = 3
keys('Calc', 'dy/dx')
assert '~ 6' in ' '.join(g.texts()), g.texts()
keys('Calc', 'Integral')
typed('0')
typed('2')
info = list(G.info().values())
assert near(str(info[1])[2:], 8 / 3 - 8, 1e-5), info
under_limit()
keys('Clear', 'Calc', 'Value')
typed('5')
assert near(G.trace.x, 5) and '21' in str(G.info()[1])
# trace steps, the next function
keys('Clear', '>')
x0 = G.trace.x
keys('>>')
assert G.trace.x > x0
keys('Next Y')
assert int(G.trace.f) == 2
# a pole: tan in radians breaks into pieces, no line across the plot
keys('Y=')
g.tap(150, 70 + 2 * 112 + 10)                              # Y3
keys('tan', 'X')
keys('Done')
keys('Graph')
c3 = G.curves()[3]
assert c3 is not None and len(list(c3.values())) >= 2
for line in c3.values():
    pts = list(line.values())
    ys = pts[1::2]
    assert all(abs(ys[k + 1] - ys[k]) < 440 for k in range(len(ys) - 1))
under_limit()
# Zoom
keys('Zoom', 'Fit')
w = G.win()
assert w.ymin < -3.9 and w.ymax > 0
keys('Zoom', 'Standard')
assert G.win().xmin == -10
# Window: Xmin above Xmax is refused
keys('Window')
g.tap(100, 72 + 10)                                        # Xmin
typed('2', '0')
assert G.win().xmin == -10 and 'below' in ' '.join(g.texts())
keys('Graph')
# Table
keys('Table')
t = g.texts()
assert 'X' in t and 'Y1' in t and '-4' in t and '5' in t, t
keys('Down')
assert int(G.tbl.first) == 13
under_limit()
assert back() is True and str(G.view()) == 'graph'         # back to the graph it came from
assert back() is True and A().screen() is None             # back to the calculator
keys('C', '2', '+', '2', '=')
assert str(A().result()) == '4'

# kept between visits, and the app reopens in the mode it was left in
open_mode('Graph')
g.restart()
g.L.execute(f"package.path = [[{HERE.replace(os.sep, '/')}/?.lua;]] .. package.path")
assert str(A().screen()) == 'Graph'
G = T('graph')
assert near(G.fns[1](1), -3)
keys('Calc')
g.tap_label('Cancel')
keys('Calc')                                               # the header button "Calc" is drawn first: the row's wins
g.tap_label('Cancel')
g.tap(30, 20)                                              # the header's Calc: back to the calculator
assert A().screen() is None

# ---------------------------------------------------------------- Stats
open_mode('Stats')
S = T('stats')
data1 = [Fraction(x) for x in ('2', '4', '4', '4', '5', '5', '7', '9', '10.5')]
data2 = [Fraction(x) for x in ('1', '3', '2', '5', '4', '6', '8', '9', '12')]
g.tap(150, 104 + 10)                                       # L1(1)
typed('2')
g.tap(150, 104 + 36 + 10)                                  # L1(2)
typed('4')
g.tap(150, 104 + 10)                                       # change L1(1)
keys('C')
typed('3')
assert str(A().D.format(S.L[1][1], 16)) == '3'
g.tap(150, 104 + 10)
keys('C')
typed()                                                    # nothing typed: deleted
assert len(S.L[1]) == 1
g.L.execute("""local S = __TEST.api.mod('stats').test
  local D = __TEST.api.D
  for k = #S.L[1], 1, -1 do S.L[1][k] = nil end
  for _k, v in ipairs({ %s }) do S.L[1][#S.L[1] + 1] = D.parse(v) end
  for _k, v in ipairs({ %s }) do S.L[2][#S.L[2] + 1] = D.parse(v) end""" % (
    ', '.join("'%s'" % float(x) for x in data1), ', '.join("'%s'" % float(x) for x in data2)))
keys('1-Var L1')
res = {str(l[1]): str(A().D.format(l[2], 16)) for l in S.res()['lines'].values()}
xs = [float(x) for x in data1]
assert near(res['mean'], statistics.mean(xs)) and near(res['SD (sample)'], statistics.stdev(xs))
assert near(res['SD (population)'], statistics.pstdev(xs)) and near(res['median'], 5)
assert near(res['Q1'], 4) and near(res['Q3'], 8) and res['n'] == '9' and near(res['max'], 10.5)
under_limit()
g.tap(20, 72 + 1 * 40 + 5)                                 # tap "mean": kept as Ans
assert near(A().ans(), statistics.mean(xs)) and 'Ans = mean' in ' '.join(g.texts())
back()
keys('2-Var')
res = {str(l[1]): str(A().D.format(l[2], 16)) for l in S.res()['lines'].values()}
ys = [float(y) for y in data2]
slope, icept = statistics.linear_regression(xs, ys)
assert near(res['y = ax + b:  a'], slope) and near(res['b'], icept), res
assert near(res['r'], statistics.correlation(xs, ys))
keys('QuadReg')
res = {str(l[1]): str(A().D.format(l[2], 16)) for l in S.res()['lines'].values()}
assert 'y = ax²+bx+c:  a' in res
keys('ExpReg')
assert 'y = a·b^x:  a' in [str(l[1]) for l in S.res()['lines'].values()]
keys('Plot')                                               # to Graph with the points
assert str(A().screen()) == 'Graph'
under_limit()
g.tap(30, 20)
# an exact parabola: QuadReg gives it back
open_mode('Stats')
g.L.execute("""local S = __TEST.api.mod('stats').test
  local D = __TEST.api.D
  for c = 1, 2 do for k = #S.L[c], 1, -1 do S.L[c][k] = nil end end
  for x = -2, 3 do S.L[1][#S.L[1] + 1] = D.parse(tostring(x)); S.L[2][#S.L[2] + 1] = D.parse(tostring(2 * x * x - 3 * x + 1)) end
  S.set_reg('QuadReg')""")
keys('2-Var')
res = {str(l[1]): str(A().D.format(l[2], 16)) for l in S.res()['lines'].values()}
assert res['y = ax²+bx+c:  a'] == '2' and res['b'] == '-3' and res['c'] == '1' and res['R²'] == '1', res
S.set_reg('LinReg')
g.tap(30, 20)

# ---------------------------------------------------------------- Distributions
open_mode('Distributions')
S = T('stats')


def distr(name, values):
    for k, d in S.DISTR.items():
        if str(d[1]) == name:
            fn = d[3]
            return fn(g.L.table_from(values))
    raise KeyError(name)


def phi(z):
    return 0.5 * (1 + math.erf(z / math.sqrt(2)))


INF = float('inf')
assert near(distr('normalcdf', [-1, 1, 0, 1]), phi(1) - phi(-1))
assert near(distr('normalcdf', [5, INF, 0, 1]), 1 - phi(5), 1e-5)  # a tail, not 1 - 0.9999997
assert near(distr('normalpdf', [1, 0, 1]), math.exp(-0.5) / math.sqrt(2 * math.pi))
assert near(distr('invNorm', [0.975, 0, 1]), 1.959963984540054, 1e-6)
assert near(distr('binompdf', [10, 0.5, 5]), math.comb(10, 5) / 1024)
assert near(distr('binomcdf', [10, 0.5, 5]), sum(math.comb(10, k) for k in range(6)) / 1024)
assert near(distr('poissonpdf', [3, 2]), math.exp(-3) * 9 / 2)
assert near(distr('poissoncdf', [3, 2]), math.exp(-3) * (1 + 3 + 4.5))
assert near(distr('geometpdf', [0.2, 3]), 0.8 ** 2 * 0.2) and near(distr('geometcdf', [0.2, 3]), 1 - 0.8 ** 3)


def t_cdf(t, df):                                          # Simpson on the density, for the check
    c = math.gamma((df + 1) / 2) / (math.sqrt(df * math.pi) * math.gamma(df / 2))
    f = lambda u: c * (1 + u * u / df) ** (-(df + 1) / 2)
    n, a = 20000, 0.0
    h = (t - a) / n
    s = f(a) + f(t) + sum((4 if k % 2 else 2) * f(a + k * h) for k in range(1, n))
    return 0.5 + s * h / 3


assert near(distr('tcdf', [-INF, 2.0, 10]), t_cdf(2.0, 10), 1e-6)
assert near(distr('invT', [t_cdf(1.5, 7), 7]), 1.5, 1e-5)
# chi² with 2 degrees of freedom: 1 - e^(-x/2)
assert near(distr('chi²cdf', [0, 3, 2]), 1 - math.exp(-1.5)) and near(distr('chi²cdf', [0, 3.841458820694124, 1]), 0.95, 1e-6)
# the form
keys('normalcdf')
g.tap(100, 72 + 10)                                        # lower
typed('-', '1')
g.tap(100, 72 + 64 + 10)                                   # upper
typed('1')
keys('Work it out')
assert any(s.startswith('~ 0.68268') for s in g.texts()), g.texts()
under_limit()
assert back() and str(S.view()) == 'distr'
g.tap(30, 20)
assert A().screen() is None

# ---------------------------------------------------------------- Solve
open_mode('Solve')
V = T('solve')
g.tap(100, 72 + 10)                                        # Left
typed('X', 'x²')
g.tap(100, 136 + 10)                                       # Right
keys('C')
typed('2')
keys('Solve')
r = sorted(float(x) for x in V.roots().values())
assert len(r) == 2 and near(r[0], -math.sqrt(2), 1e-6) and near(r[1], math.sqrt(2), 1e-6), r
# a pole is no solution; a touching zero is one
F = V.F
f1 = F.compile(g.L.eval("{ {t='num', s='1'}, {t='op', s='÷'}, {t='const', s='x'} }"))
zero = F.compile(g.L.eval("{ {t='num', s='0'} }"))
assert len(list(V.solve_all(f1, zero, -10, 10, 10).values())) == 0
sq = F.compile(g.L.eval("{ {t='lp', s='('}, {t='const', s='x'}, {t='op', s='-'}, {t='num', s='1'}, {t='rp', s=')'}, {t='post', s='²'} }"))
r = list(V.solve_all(sq, zero, -10, 10, 10).values())
assert len(r) == 1 and abs(r[0] - 1) < 1e-4, r
under_limit()
g.tap(20, 344 + 5)                                         # keep a solution as Ans
assert 'Ans' in ' '.join(g.texts())
g.tap(30, 20)

# ---------------------------------------------------------------- Matrix
open_mode('Matrix')
X = T('matrix')


def cell(i, j):
    return (12 + (j - 1) * 114 + 20, 124 + (i - 1) * 48 + 10)


for (i, j), v in {(1, 1): '2', (1, 2): '1', (2, 1): '1', (2, 2): '3'}.items():
    g.tap(*cell(i, j))
    keys('C')
    typed(v)
keys('det')
assert str(A().D.format(X.result(), 16)) == '5'
keys('inverse')
res = X.result()
assert [[str(A().D.format(res.v[i][j], 16)) for j in (1, 2)] for i in (1, 2)] == [['0.6', '-0.2'], ['-0.2', '0.4']]
keys('Store')
g.tap_label('B')
keys('×')
g.tap_label('B')                                           # A × A^-1 = I
res = X.result()
assert [[str(A().D.format(res.v[i][j], 16)) for j in (1, 2)] for i in (1, 2)] == [['1', '0'], ['0', '1']]
under_limit()
# rref solves 2x + y = 5, x + 3y = 10 -> x = 1, y = 3
g.tap_label('2 x 2')
g.tap_label('2')
g.tap_label('3')
g.tap(*cell(1, 3)); keys('C'); typed('5')
g.tap(*cell(2, 3)); keys('C'); typed('1', '0')
keys('rref')
res = X.result()
assert str(A().D.format(res.v[1][3], 16)) == '1' and str(A().D.format(res.v[2][3], 16)) == '3'
keys('det')
assert 'square' in str(X.msg())
under_limit()
g.tap(30, 20)

# ---------------------------------------------------------------- Units
open_mode('Units')
Un = T('units')
D = A().D
assert Un.convert(1, 8, 4, D.parse('1')) == '1.609344'                    # mi -> km
assert Un.convert(3, 1, 2, D.parse('100')) == '212' and Un.convert(3, 2, 1, D.parse('-40')) == '-40'
assert near(Un.convert(11, 2, 1, D.parse('1')), 180 / math.pi, 1e-12)
assert Un.convert(8, 6, 10, D.parse('1')) == '0.9094947017729282'           # TB -> TiB
keys('Value')
keys('C')
typed('2')
assert '2 m is' in g.texts() and '200' in g.texts()
g.tap(20, 196 + 3 * 46 + 10)                                               # km: type in km now
assert '0.002 km is' in g.texts(), g.texts()
under_limit()
g.tap(30, 20)

# ---------------------------------------------------------------- Base
open_mode('Base')
B = T('base')
B.set_base(1)                                              # HEX
for k in ('F', 'F', 'AND', '0', 'F', '='):
    B.press(k)
assert int(B.value()) == 15
B.press('Clr'); B.set_base(2)
for k in ('1', '±', '='):
    B.press(k)
assert str(B.show(B.value(), 1)) == 'FFFFFFFF' and str(B.show(B.value(), 4)).replace(' ', '') == '1' * 32
B.press('Clr')
for k in ('1', '<<', '3', '1', '='):
    B.press(k)
assert int(B.value()) == -2147483648
for k in ('>>', '3', '1', '='):
    B.press(k)
assert int(B.value()) == 1                                 # logical shift
B.press('Clr')
for k in ('7', '±', '÷', '2', '='):
    B.press(k)
assert int(B.value()) == -3                                # truncating
for k in ('4', '2', '9', '4', '9', '6', '7', '2', '9', '5', '+', '1', '='):
    B.press(k)
assert int(B.value()) == 0                                 # 4294967295 + 1 wraps
B.press('NOT')
assert int(B.value()) == -1
B.press('Keep')
assert str(A().ans()) == '-1' and 'Ans = -1' in ' '.join(g.texts())
under_limit()
g.tap(30, 20)

# ---------------------------------------------------------------- Finance
open_mode('Finance')
Fi = T('finance')
tv = Fi.tvm
tv.n, tv.i, tv.pv, tv.fv, tv.py = D.parse('360'), D.parse('6'), D.parse('200000'), D.parse('0'), D.parse('12')
Fi.solve('pmt')
r = 0.005
want = -200000 * r / (1 - (1 + r) ** -360)
assert near(D.format(tv.pmt, 16), want, 1e-12), D.format(tv.pmt, 16)
Fi.solve('i')
assert near(D.format(tv.i, 16), 6, 1e-5)
tv.i = D.parse('6')
Fi.solve('n')
assert near(D.format(tv.n, 16), 360, 1e-4)
tv.n = D.parse('360')
Fi.solve('pv')
assert near(D.format(tv.pv, 16), 200000, 1e-12)
Fi.set_begin(True)
Fi.solve('pmt')
assert near(D.format(tv.pmt, 16), want / (1 + r), 1e-12)
Fi.set_begin(False)
Fi.solve('pmt')
keys('Schedule')
sched, total = Fi.sched()
assert near(D.format(total, 16), -want * 360 - 200000, 1e-9) and abs(float(D.format(sched[360][3], 16))) < 1e-6
under_limit()
keys('TVM', 'Percent')
t = ' '.join(g.texts())
assert 'Change: +25 %' in t and '15 % of the value: 37.5' in t, t
under_limit()
g.tap(30, 20)

# ---------------------------------------------------------------- Dates
open_mode('Dates')
Dt = T('dates')
dfc = Dt.days_from_civil
for (y, m, d) in ((2024, 1, 1), (1999, 12, 31), (2026, 11, 9), (1900, 3, 1)):
    assert dfc(y, m, d) == (datetime.date(y, m, d) - datetime.date(1970, 1, 1)).days
for (y, m, d) in ((2021, 1, 3), (2026, 11, 9), (2020, 12, 31), (2027, 1, 1)):
    wk, wy = Dt.iso_week(dfc(y, m, d))
    iso = datetime.date(y, m, d).isocalendar()
    assert wk == iso[1] and (wy is None or wy == iso[0]), (y, m, d, wk, wy, iso)
assert tuple(Dt.span(dfc(2024, 1, 31), dfc(2024, 3, 1))) == (0, 1, 1)
assert tuple(Dt.span(dfc(2020, 2, 29), dfc(2026, 11, 9))) == (6, 8, 11)
Dt.set(dfc(2024, 1, 1), dfc(2024, 12, 31))
t = g.texts()
assert '365 days  =  52 weeks 1 day' in t and '11 months, 30 days' in t, t
g.tap(100, 70 + 10)                                         # the first date, typed
keys('C')
typed('2', '0', '2', '6', '1', '1', '0', '9')
assert 'Mon 9 Nov 2026' in g.texts()
g.tap(100, 70 + 10)
keys('C')
typed('2', '0', '2', '6', '0', '2', '3', '0')
assert 'not a date' in ' '.join(g.texts())
under_limit()
g.tap(30, 20)

# Basic still works as before, and a cancelled question changes nothing
keys('C', '1', '+', '1', '=')
assert str(A().result()) == '2'
open_mode('Dates')
g.tap(100, 70 + 10)
keys('5', 'Cancel')
assert str(A().screen()) == 'Dates' and not A().editing()
g.tap(30, 20)
assert str(A().result()) == '2'
g.no_err()
print('calculator mode tests passed')
