"""Offline test of Notebook (gamekit harness; the app folder, the clock and the docked keyboard
stood in): the note format (title, folder, tags, dates, paragraphs; a file written on a computer
without them; a paragraph too long for the keyboard cut), file names from titles, search folding
(Turkish İ / I / ı), and the app by taps: a new note, paragraphs written with Enter as a new line
and Save, a blank line splitting one, an empty one deleted, Back while typing asking to save,
folder and tags, sorting, the folder and tag filters, a search through all notes, renaming,
deleting, the index kept between starts, Back and the draw commands.

  python -I apps/notebook/test_notebook.py
"""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(HERE)), 'tools', 'gamekit'))
from harness import Game  # noqa: E402

sys.stdout.reconfigure(encoding='utf-8')
fails = []


def check(ok, what):
    print(('ok    ' if ok else 'FAIL  ') + what)
    if not ok:
        fails.append(what)


g = Game(HERE)
L = g.L
L.execute('''
files = {}
nowmin = 0
timers = {}
ctx.after = function(self, ms, fn) timers[#timers + 1] = fn; return true end
function run_timers() while #timers > 0 do local f = table.remove(timers, 1); f(ctx); fake_ms = fake_ms + 400 end end
ctx.clock.now = function(self) nowmin = nowmin + 1; return { valid = true, year = 2026, month = 11, day = 6, hour = 14, minute = nowmin % 60 } end
ctx.files = {
  path = '/AppFiles/notebook',
  list = function(self)
    local out = {}
    for n, d in pairs(files) do out[#out + 1] = { name = n, size = #d } end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
  end,
  read = function(self, n, off, len)
    local d = files[n]
    if not d then return nil, 'not_found' end
    off, len = off or 0, len or 65536
    return d:sub(off + 1, off + len)
  end,
  write = function(self, n, d) files[n] = d; return true end,
  remove = function(self, n) files[n] = nil; return true end,
  exists = function(self, n) return files[n] ~= nil end,
}
ctx.input.keyboard_h = 436
editing, current_ed = nil, nil
ctx.input.edit = function(self, opts)
  assert(opts.multiline and opts.enter == 'newline' and opts.max_chars == 512, 'docked: multiline, Enter a new line')
  editing = opts
  local ed = { cur = opts.text }
  function ed:set_text(t) self.cur = t; return true end
  function ed:text() return editing and self.cur or nil end
  function ed:close() local t = editing and self.cur or nil; editing = nil; return t end
  current_ed = ed
  return ed
end
function type_text(t) current_ed.cur = t; editing.on_change(ctx, t) end
function press_back() local o = editing; editing = nil; o.on_end(ctx, current_ed.cur, 'back') end
''')
g.restart()
A = lambda: g.api
B = g.api.B
ctx = g.L.eval('ctx')
back = L.eval("function(ph) return on_input(ctx, { type = 'key', key = 'back', phase = ph }) end")


def typed(s):
    L.eval('inputs[#inputs]')(ctx, s)


def files():
    return {str(k): str(v) for k, v in L.eval('files').items()}


def paras():
    return [str(p) for p in A().cur().n.paras.values()]


def save():
    g.tap(470, 20)


def cancel():
    g.tap(20, 20)


def tap_para(k):
    """the k-th block on the note's page"""
    blk = A().note_pages()[1][k]
    g.tap(100, int(blk.y) + 5)


# ---------------------------------------------------------------- the format
n = B.parse('Shopping list\nfolder: Home\ntags: weekly, Market, weekly\nedited: 2026-11-06 14:30\n\nMilk\nBread\n\n\nEggs\n')
check(n.title == 'Shopping list' and n.folder == 'Home' and list(n.tags.values()) == ['weekly', 'Market']
      and list(n.paras.values()) == ['Milk\nBread', 'Eggs'], 'a note file: title, folder, tags (no doubles), paragraphs')
check(str(B.format(n)).startswith('Shopping list\nfolder: Home\ntags: weekly, Market\nedited: 2026-11-06 14:30\n\nMilk\nBread\n\nEggs\n'),
      'written back the same way')
n = B.parse('Ideas from the PC\r\nfirst line\r\n\r\nsecond')
check(n.title == 'Ideas from the PC' and list(n.paras.values()) == ['first line', 'second'], 'a file written elsewhere (no header, CRLF)')
long = ' '.join(['word%03d' % i for i in range(150)])
ps = list(B.paragraphs(long).values())
check(len(ps) == 3 and all(len(p) <= 512 for p in ps) and ' '.join(ps) == long, f'a paragraph over 512 characters is cut at spaces: {[len(p) for p in ps]}')
check(B.fold('İSTANBUL Işık ÇĞÖŞÜ') == 'istanbul işik çğöşü', 'search folds Turkish capitals and the dotless i')
taken = L.eval("function(t) local s = {} for _, v in ipairs(t) do s[v] = true end return function(n) return s[n] end end")
check(B.file_name('a/b: c? <d>', taken(L.table_from([]))) == 'a b c d.txt', 'a file name from a title: only letters the card takes')
check(B.file_name('Plan', taken(L.table_from(['Plan.txt', 'Plan 2.txt']))) == 'Plan 3.txt', 'two notes with one title get two files')
check(B.file_name('con', taken(L.table_from([]))) == 'con_.txt', 'a reserved name is changed')

# ---------------------------------------------------------------- the app by taps
check('No notes yet: tap New note.' in g.texts(), 'an empty notebook says how to start')
g.tap_label('New note')
typed('Shopping list')
check(A().screen() == 'edit' and A().edit().i is None, 'a new note opens a new paragraph to write')
L.eval('type_text')('Milk\nBread')
save()
check(A().screen() == 'note' and paras() == ['Milk\nBread'] and 'Shopping list.txt' in files(),
      'Save keeps the paragraph, with its new line, in Shopping list.txt')
check('edited: 2026-11-06 14:' in files()['Shopping list.txt'] and 'created: 2026-11-06 14:' in files()['Shopping list.txt'], 'dates written')
g.tap_label('Add')
L.eval('type_text')('Eggs\n\nButter')
save()
check(paras() == ['Milk\nBread', 'Eggs', 'Butter'], 'a blank line in a paragraph makes two')
tap_para(1)
check(A().screen() == 'edit' and A().edit().i == 1 and str(A().edit().text) == 'Milk\nBread', 'tap a paragraph to edit it')
L.eval('type_text')('')
save()
check(paras() == ['Eggs', 'Butter'] and A().msg() == 'Paragraph deleted.', 'saved empty: the paragraph is deleted')
tap_para(2)
L.eval('type_text')('Butter, salted')
L.eval('press_back')()
check('Save the changes?' in g.texts(), 'Back while typing asks before dropping a change')
g.tap_label('Save')
check(paras() == ['Eggs', 'Butter, salted'], 'and Save keeps it')
tap_para(1)
cancel()
check(paras() == ['Eggs', 'Butter, salted'] and A().screen() == 'note', 'Cancel leaves it as it was')

# folder and tags
g.tap(430, 20)                                     # Menu
g.tap_label('Folder')
g.tap_label('New folder...')
typed('Home')
g.tap(430, 20)
g.tap_label('Tags')
typed('weekly, market')
f = files()['Shopping list.txt']
check('folder: Home' in f and 'tags: weekly, market' in f, 'folder and tags written to the note')
g.tap_label('List')

# a second note, with Turkish text, and a third without a folder
g.tap_label('New note')
typed('İş planı')
L.eval('type_text')('Pazartesi İSTANBUL toplantısı\nSalı rapor')
save()
g.tap_label('List')
g.tap_label('New note')
typed('Books to read')
L.eval('type_text')('Middlemarch')
save()
g.tap_label('List')
names = [str(e.title) for e in A().visible().values()]
check(names == ['Books to read', 'İş planı', 'Shopping list'], f'the list, last edited first: {names}')
g.tap_label('Edited')
g.tap_label('Title A-Z')
names = [str(e.title) for e in A().visible().values()]
check(names == ['Books to read', 'İş planı', 'Shopping list'], f'sorted by title: {names}')
g.tap_label('Folders')
g.tap_label('Home (1)')
check([str(e.title) for e in A().visible().values()] == ['Shopping list'] and 'Home' in g.texts(), 'the folder filter')
g.tap_label('Home')
g.tap_label('All folders (3)')
g.tap_label('Tags')
g.tap_label('market (1)')
check([str(e.title) for e in A().visible().values()] == ['Shopping list'], 'the tag filter')
g.tap_label('#market')
g.tap_label('All tags')

# search through all notes
g.tap_label('Search')
typed('istanbul')
L.eval('run_timers')()
vis = [str(e.title) for e in A().visible().values()]
check(vis == ['İş planı'] and any('İSTANBUL' in t for t in g.texts()), f'a search through every note, with the line found: {vis}')
check(any(t.startswith('Found in 1 of 3') for t in g.texts()), 'how many notes have it')
g.tap_label('Clear')
check(A().search() is None and len(A().visible()) == 3, 'Clear ends the search')

# rename and delete
g.tap_label('Books to read')
g.tap(430, 20)
g.tap_label('Rename')
typed('Reading list')
check('Reading list.txt' in files() and 'Books to read.txt' not in files() and files()['Reading list.txt'].startswith('Reading list\n'),
      'Rename writes the new file and removes the old one')
g.tap(430, 20)
g.tap_label('Delete')
g.tap_label('Delete')
check('Reading list.txt' not in files() and A().screen() == 'list' and len(A().entries()) == 2, 'Delete removes the note')

# a file put on the card from a computer, and the index between starts
L.execute("files['From the PC.txt'] = 'Ideas\\n' .. string.rep('long line of text ', 40) .. '\\n\\nshort'")
g.L.execute('on_leave(ctx)')
g.restart()
titles = sorted(str(e.title) for e in A().entries().values())
check(titles == ['Ideas', 'Shopping list', 'İş planı'], f'after a restart: the notes, and one added on a computer: {titles}')
check('Title' in g.texts() and 'Folders' in g.texts() and 'Tags' in g.texts(), 'the sort and the filters are kept between starts')
idx = str(L.eval('store["index.txt"]'))
check('Shopping list.txt\t' in idx and 'Home' in idx, 'the index keeps titles, folders and tags')
g.tap_label('Ideas')
check(len(A().cur().n.paras) == 3, 'its long paragraph is cut for the keyboard (720 characters: two parts, then "short")')
check(back('up') is True and A().screen() == 'list', 'Back leaves a note for the list')
check(back('up') is False, 'Back on the list returns false: the host offers to exit')

# a crowded list draws within the frame
for i in range(30):
    L.execute(f"files['Note {i:02d}.txt'] = 'Note {i:02d}\\ntags: a, b\\n\\n' .. string.rep('text ', 60)")
g.restart()
n = g.commands()
check(n < 300 and '1/5' in g.texts(), f'33 notes, a page of 7 at a time: {n} draw commands')

print('\n' + ('all passed' if not fails else f'{len(fails)} FAILED'))
sys.exit(1 if fails else 0)
