-- A book's taste, guessed from its author and title (the reader tells an app nothing more): a
-- list of well-known authors, English and Turkish, and words in titles, in English and Turkish.
-- Eight tastes; nil when nothing matches. A guess, not a library catalogue: an author's best
-- known kind of book stands for all of theirs.

local T = {}

T.KINDS = { 'horror', 'mystery', 'romance', 'fantasy', 'scifi', 'adventure', 'classic', 'nonfiction' }
T.NAMES = {
  horror = 'a horror fan', mystery = 'a detective', romance = 'a romantic', fantasy = 'a dreamer of dragons',
  scifi = 'a space cadet', adventure = 'an adventurer', classic = 'a classicist', nonfiction = 'a know-it-all',
}

-- surnames (or whole names, for the common surnames) of writers best known for one kind of book
local AUTHORS = {
  horror = { 'stephen king', 'lovecraft', 'shirley jackson', 'anne rice', 'clive barker', 'dean koontz', 'bram stoker',
             'mary shelley', 'peter straub', 'joe hill', 'paul tremblay', 'grady hendrix', 'stephen graham jones',
             'ramsey campbell', 'william peter blatty', 'ira levin', 'susan hill', 'algernon blackwood', 'm. r. james',
             'thomas ligotti', 'adam nevill', 'josh malerman', 'richard matheson', 'shaun hutson' },
  mystery = { 'agatha christie', 'arthur conan doyle', 'conan doyle', 'dorothy l. sayers', 'raymond chandler',
              'dashiell hammett', 'georges simenon', 'p. d. james', 'ruth rendell', 'ian rankin', 'tana french',
              'louise penny', 'jo nesbo', 'jo nesbø', 'stieg larsson', 'henning mankell', 'harlan coben', 'gillian flynn',
              'michael connelly', 'lee child', 'dan brown', 'john grisham', 'patricia highsmith', 'wilkie collins',
              'edgar allan poe', 'rex stout', 'ngaio marsh', 'elizabeth george', 'anthony horowitz', 'richard osman',
              'robert galbraith', 'james patterson', 'karin slaughter', 'tess gerritsen', 'camilla lackberg',
              'ahmet ümit', 'ahmet umit', 'mehmet murat somer', 'keigo higashino', 'arnaldur indridason' },
  romance = { 'jane austen', 'nicholas sparks', 'colleen hoover', 'nora roberts', 'danielle steel', 'jojo moyes',
              'julia quinn', 'emily henry', 'sally rooney', 'diana gabaldon', 'lisa kleypas', 'sarah j. maas',
              'rainbow rowell', 'mhairi mcfarlane', 'beth o\'leary', 'tessa dare', 'georgette heyer', 'barbara cartland',
              'sophie kinsella', 'cecelia ahern', 'tracy wolff', 'ali hazelwood', 'christina lauren', 'kerem görsev',
              'reşat nuri güntekin', 'resat nuri guntekin', 'kahraman tazeoğlu' },
  fantasy = { 'tolkien', 'j. k. rowling', 'rowling', 'george r. r. martin', 'brandon sanderson', 'terry pratchett',
              'ursula k. le guin', 'robert jordan', 'patrick rothfuss', 'neil gaiman', 'c. s. lewis', 'robin hobb',
              'joe abercrombie', 'n. k. jemisin', 'leigh bardugo', 'rick riordan', 'christopher paolini',
              'terry brooks', 'raymond e. feist', 'steven erikson', 'mark lawrence', 'naomi novik', 'v. e. schwab',
              'r. f. kuang', 'andrzej sapkowski', 'philip pullman', 'michael ende', 'cornelia funke', 'susanna clarke',
              'lewis carroll', 'l. frank baum', 'garth nix', 'scott lynch', 'samantha shannon', 'rebecca yarros' },
  scifi = { 'isaac asimov', 'asimov', 'arthur c. clarke', 'frank herbert', 'philip k. dick', 'ray bradbury',
            'robert a. heinlein', 'heinlein', 'iain m. banks', 'kim stanley robinson', 'liu cixin', 'cixin liu',
            'william gibson', 'neal stephenson', 'dan simmons', 'orson scott card', 'andy weir', 'h. g. wells',
            'jules verne', 'stanislaw lem', 'stanisław lem', 'larry niven', 'peter f. hamilton', 'alastair reynolds',
            'martha wells', 'becky chambers', 'ann leckie', 'james s. a. corey', 'blake crouch', 'douglas adams',
            'ted chiang', 'octavia e. butler', 'kurt vonnegut', 'aldous huxley', 'george orwell', 'pierce brown',
            'adrian tchaikovsky', 'john scalzi', 'vernor vinge' },
  adventure = { 'robert louis stevenson', 'alexandre dumas', 'jack london', 'h. rider haggard', 'clive cussler',
                'wilbur smith', 'jon krakauer', 'rudyard kipling', 'daniel defoe', 'patrick o\'brian',
                'arturo perez-reverte', 'arturo pérez-reverte', 'paulo coelho', 'yann martel', 'karl may',
                'emilio salgari', 'mark twain', 'herman melville', 'ernest hemingway', 'hammond innes',
                'alistair maclean', 'matthew reilly', 'james rollins' },
  classic = { 'charles dickens', 'dickens', 'leo tolstoy', 'tolstoy', 'tolstoy', 'lev tolstoy', 'fyodor dostoevsky', 'dostoyevsky', 'dostoevsky', 'dostoyevski',
              'victor hugo', 'gustave flaubert', 'honoré de balzac', 'balzac', 'emile zola', 'émile zola',
              'thomas hardy', 'george eliot', 'charlotte brontë', 'charlotte bronte', 'emily brontë', 'emily bronte',
              'virginia woolf', 'james joyce', 'franz kafka', 'kafka', 'anton chekhov', 'ivan turgenev', 'nikolai gogol',
              'marcel proust', 'thomas mann', 'hermann hesse', 'albert camus', 'jean-paul sartre', 'gabriel garcía márquez',
              'gabriel garcia marquez', 'jorge luis borges', 'miguel de cervantes', 'homer', 'dante alighieri',
              'william shakespeare', 'shakespeare', 'f. scott fitzgerald', 'john steinbeck', 'william faulkner',
              'toni morrison', 'harper lee', 'oscar wilde', 'henry james', 'edith wharton', 'mikhail bulgakov',
              'vladimir nabokov', 'stefan zweig', 'italo calvino', 'umberto eco', 'kazuo ishiguro', 'haruki murakami',
              'orhan pamuk', 'sabahattin ali', 'yaşar kemal', 'yasar kemal', 'oğuz atay', 'oguz atay', 'orhan kemal',
              'peyami safa', 'halide edib', 'ahmet hamdi tanpınar', 'ahmet hamdi tanpinar', 'elif şafak', 'elif safak',
              'zülfü livaneli', 'zulfu livaneli', 'nazım hikmet', 'nazim hikmet', 'aziz nesin', 'sait faik',
              'halit ziya uşaklıgil', 'cengiz aytmatov', 'chinua achebe', 'milan kundera', 'josé saramago', 'jose saramago' },
  nonfiction = { 'yuval noah harari', 'harari', 'malcolm gladwell', 'daniel kahneman', 'james clear', 'carl sagan',
                 'stephen hawking', 'richard dawkins', 'jared diamond', 'bill bryson', 'mary beard', 'cal newport',
                 'brené brown', 'brene brown', 'mark manson', 'dale carnegie', 'stephen r. covey', 'robert greene',
                 'michelle obama', 'walter isaacson', 'oliver sacks', 'neil degrasse tyson', 'steven pinker',
                 'nassim nicholas taleb', 'ilber ortaylı', 'ilber ortayli', 'celal şengör', 'doğan cüceloğlu',
                 'dogan cuceloglu', 'adam grant', 'simon sinek', 'atul gawande', 'siddhartha mukherjee',
                 'rebecca skloot', 'tara westover', 'viktor frankl', 'marcus aurelius', 'seneca' },
}

-- words in titles, English and Turkish (matched as whole words, after lowering)
local WORDS = {
  horror = { 'ghost', 'ghosts', 'haunted', 'haunting', 'vampire', 'vampires', 'dracula', 'zombie', 'zombies', 'demon',
             'demons', 'curse', 'cursed', 'horror', 'terror', 'nightmare', 'nightmares', 'possessed', 'exorcist',
             'korku', 'hayalet', 'cinler', 'vampir', 'lanet', 'kâbus', 'kabus', 'şeytan', 'seytan' },
  mystery = { 'murder', 'murders', 'detective', 'mystery', 'mysteries', 'killer', 'killing', 'crime', 'poison',
              'clue', 'thief', 'cinayet', 'cinayeti', 'dedektif', 'katil', 'gizem', 'esrarengiz', 'polisiye' },
  romance = { 'love', 'lover', 'lovers', 'heart', 'hearts', 'kiss', 'bride', 'wedding', 'duke', 'marry', 'romance',
              'darling', 'beloved', 'aşk', 'sevgili', 'kalp', 'gelin', 'öpücük', 'evlilik', 'sevda' },
  fantasy = { 'dragon', 'dragons', 'sword', 'magic', 'wizard', 'wizards', 'throne', 'thrones', 'kingdom', 'crown',
              'quest', 'elf', 'elves', 'sorcerer', 'witch', 'fae', 'realm', 'ejderha', 'büyü', 'buyu', 'büyücü',
              'kılıç', 'kilic', 'krallık', 'krallik', 'taht', 'cadı', 'cadi', 'peri' },
  scifi = { 'star', 'stars', 'space', 'robot', 'robots', 'planet', 'galaxy', 'mars', 'alien', 'aliens', 'future',
            'android', 'cyber', 'foundation', 'dune', 'starship', 'uzay', 'gezegen', 'galaksi', 'yıldız', 'yildiz',
            'gelecek', 'uzaylı', 'uzayli' },
  adventure = { 'island', 'treasure', 'pirate', 'pirates', 'voyage', 'journey', 'sea', 'jungle', 'expedition',
                'adventure', 'adventures', 'wild', 'ada', 'adası', 'hazine', 'korsan', 'korsanlar', 'yolculuk', 'macera',
                'deniz', 'keşif', 'kesif' },
  nonfiction = { 'history', 'guide', 'habits', 'science', 'economics', 'psychology', 'biography', 'memoir',
                 'brain', 'mind', 'leadership', 'success', 'tarih', 'tarihi', 'rehber', 'bilim', 'psikoloji',
                 'alışkanlık', 'aliskanlik', 'başarı', 'basari', 'hayatın', 'kişisel' },
}

local by_author, by_word = {}, {}
for kind, list in pairs(AUTHORS) do for _, a in ipairs(list) do by_author[a] = kind end end
for kind, list in pairs(WORDS) do for _, w in ipairs(list) do by_word[w] = kind end end

-- lower case for the letters that matter here (ASCII, and the Turkish capitals İ Ş Ğ Ü Ö Ç; a
-- capital I stays i, as English names need)
local CAP = { ['İ'] = 'i', ['Ş'] = 'ş', ['Ğ'] = 'ğ', ['Ü'] = 'ü', ['Ö'] = 'ö', ['Ç'] = 'ç',
              ['Â'] = 'â', ['É'] = 'é', ['Ø'] = 'ø' }
local function lower(s)
  s = tostring(s or '')
  s = s:gsub(utf8.charpattern, function(ch) return CAP[ch] or ch:lower() end)
  return s
end

-- "King, Stephen" -> "stephen king"; spaces tidied; initials as "j. r. r."
local function author_key(a)
  a = lower(a)
  local last, first = a:match('^%s*([^,]+),%s*(.+)$')
  if last then a = first .. ' ' .. last end
  a = a:gsub('%.(%S)', '. %1'):gsub('%s+', ' '):gsub('^ ', ''):gsub(' $', '')
  return a
end
T.author_key = author_key

function T.guess(title, author)
  local a = author_key(author)
  if a ~= '' then
    if by_author[a] then return by_author[a] end
    -- the surname alone, for the entries that are one word (tolkien, asimov ...)
    local surname = a:match('(%S+)$')
    if surname and by_author[surname] then return by_author[surname] end
    -- a listed name inside the field ("by Stephen King and Owen King")
    for name, kind in pairs(by_author) do
      if name:find(' ', 1, true) and a:find(name, 1, true) then return kind end
    end
  end
  local t = lower(title)
  -- whole words: a word made of letters (any script) between non-letters
  for w in t:gmatch('[%a\128-\255]+') do
    local kind = by_word[w]
    if kind then return kind end
  end
  return nil
end

return T
