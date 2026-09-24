// t60 - DRAWING PAGES (2026-09-23). His ask: "לפתוח כמה דפים לסירטוטים שונים -
// סירטוט שהוא רק סירטוט ולא 3D". Tab 0 is the house; a drawing page keeps
// its own blue lines and never goes to the model.
const api = require('./run.js');
const g = (n) => api.get(n), c = (n, ...a) => api.call(n, ...a), s = (n, v) => api.set(n, v);
let fails = 0;
const ok = (n, cd, x) => { console.log((cd ? 'PASS  ' : 'FAIL  ') + n + (cd ? '' : '   << ' + JSON.stringify(x))); if (!cd) fails++; };

// the house has a model wall and one blue wall
s('walls', [{ id: 'w1', sx: 0, sy: 0, ex: 100, ey: 0, syms: [] }]);
s('pending', [{ sx: 0, sy: 0, ex: 0, ey: 80 }]);
s('pendingSketches', []); s('guides', [{ x1: 0, y1: 5, x2: 9, y2: 5 }]); s('dims', []); s('anchors', {});
s('pages', []); s('activePage', 0); s('homeStash', null);

c('newPage');
ok('a new tab opens and is the active one', g('activePage') === 1 && g('pages').length === 1, [g('activePage'), g('pages').length]);
ok('the drawing page starts empty', g('pending').length === 0 && g('guides').length === 0, [g('pending'), g('guides')]);
ok('the model walls are not on the drawing page', g('walls').length === 0, g('walls'));

// draw on the page
s('pending', [{ sx: 10, sy: 10, ex: 50, ey: 10 }, { sx: 50, sy: 10, ex: 50, ey: 40 }]);
let sent = null;
global.sketchup.apply_walls = (j) => { sent = j; };
c('applyPending');
ok('Apply on a drawing page sends nothing to the model', sent === null && g('pending').length === 2, sent);

// a model sync while on the page does not put the walls on it
c('loadWalls', [{ id: 'w1', sx: 0, sy: 0, ex: 100, ey: 0, syms: [] }, { id: 'w2', sx: 0, sy: 0, ex: 0, ey: 100, syms: [] }]);
ok('a sync while on the page keeps the page clean', g('walls').length === 0, g('walls'));

// back home
c('goPage', 0);
ok('home has its blue wall and its guide again', g('pending').length === 1 && g('guides').length === 1, [g('pending'), g('guides')]);
ok('home has the synced model walls', g('walls').length === 2, g('walls').length);
ok('the page kept its two lines', g('pages')[0].pending.length === 2, g('pages')[0]);

// the draft carries the pages
const d = JSON.parse(c('draftJson'));
ok('the draft holds home as before', d.pending.length === 1 && d.guides.length === 1, d);
ok('and the pages with it', d.pages.length === 1 && d.pages[0].pending.length === 2 && d.page === 0, d.pages);

// reopen: the draft comes back with the page open
s('pages', []); s('pending', []); s('guides', []); s('activePage', 0); s('homeStash', null);
c('goPage', 0);
d.page = 1;
c('restoreDraft', JSON.stringify(d));
ok('after reopen the editor is on the house (the picture lands there)', g('activePage') === 0 && g('pending').length === 1 && g('guides').length === 1, [g('activePage'), g('pending')]);
c('goPage', 1);
ok('and the drawing page is there with its lines', g('pending').length === 2, g('pending'));
c('goPage', 0);

// two pages do not mix
c('newPage'); s('pending', [{ sx: 1, sy: 1, ex: 2, ey: 2 }]);
c('goPage', 1);
ok('page 1 still has two lines, page 2 one', g('pending').length === 2 && g('pages')[1].pending.length === 1, g('pages'));

// the background picture stays on the house; a new page is blank
c('goPage', 0);
s('underImg', { width: 100, height: 50 }); s('underScale', 2); s('calib', { a: 1 });
c('newPage');
ok('a new page has no background picture', g('underImg') === null && g('calib') === null, [g('underImg'), g('calib')]);
s('underImg', { width: 7, height: 7 });
c('goPage', 0);
ok('home has its picture back, to scale', g('underImg') && g('underImg').width === 100 && g('underScale') === 2, [g('underImg'), g('underScale')]);
c('goPage', g('pages').length);
ok('the page keeps the picture it was given', g('underImg') && g('underImg').width === 7, g('underImg'));
c('goPage', 0);

// the rooms' dashed boxes stay with the house
s('rooms', [{ id: 'r1', name: 'Room 1', pts: [0, 0, 10, 0, 10, 10, 0, 10] }]); s('ghosts', [{ sx: 0, sy: 0, ex: 1, ey: 1 }]);
c('newPage');
ok('a drawing page shows no rooms and no level below', g('rooms').length === 0 && g('ghosts').length === 0, [g('rooms'), g('ghosts')]);
c('loadRooms', [{ id: 'r1' }, { id: 'r2' }]);
ok('a room sync on the page stays off the page', g('rooms').length === 0, g('rooms'));
c('goPage', 0);
ok('home has its rooms again, synced', g('rooms').length === 2 && g('ghosts').length === 1, [g('rooms'), g('ghosts')]);

console.log(fails ? ('t60 ' + fails + ' FAILED') : 't60 OK');
process.exit(fails ? 1 : 0);
