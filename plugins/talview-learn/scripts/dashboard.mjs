#!/usr/bin/env node
// Personal learning dashboard. Reads the journal, the concept library and the lesson
// ledger; serves them locally. Nothing is uploaded and nothing is deployed.
//
//   node dashboard.mjs [--port 4455] [--no-open]
//
// It is a server rather than a static file for one reason: marking a concept reviewed
// has to WRITE BACK to the ledger. In a static page that state would live in the
// browser, die with the tab, and never follow you to another devpod.

import { createServer } from 'node:http';
import { readdirSync, readFileSync, writeFileSync, existsSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';

const LADDER = [1, 3, 7, 21, 60];
const root = process.env.TLV_STATE_ROOT
  || (process.env.CLAUDE_CONFIG_DIR ? join(process.env.CLAUDE_CONFIG_DIR, 'talview') : null)
  || join(process.env.TLV_HOME || process.env.HOME, '.talview');
const DIRS = { journal: join(root, 'journal'), concepts: join(root, 'concepts'), lessons: process.env.TLV_LESSONS_DIR || join(root, 'lessons') };
for (const d of Object.values(DIRS)) if (!existsSync(d)) mkdirSync(d, { recursive: true });

const port = Number((process.argv.find(a => a.startsWith('--port=')) || '').split('=')[1]
  || (process.argv[process.argv.indexOf('--port') + 1] || 0)) || 4455;

// LOCAL dates, not UTC. The shell scripts stamp `date +%Y-%m-%d`, which is local, so a
// UTC stamp here disagrees with them by a day for anyone east or west of Greenwich —
// and every review interval inherits that error.
const today = () => { const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`; };
const daysSince = s => {
  if (!s || s === 'never') return 1e9;
  const [y, m, d] = s.split('-').map(Number);
  if (!y || !m || !d) return 1e9;
  const then = new Date(y, m - 1, d), now = new Date(); now.setHours(0, 0, 0, 0);
  return Math.floor((now - then) / 864e5);
};
const read = f => { try { return readFileSync(f, 'utf8'); } catch { return ''; } };
const ls = d => { try { return readdirSync(d); } catch { return []; } };

function parseMd(text) {
  const m = text.match(/^---\n([\s\S]*?)\n---\n?([\s\S]*)$/);
  if (!m) return { fm: {}, body: text };
  const fm = {};
  for (const line of m[1].split('\n')) {
    const i = line.indexOf(':');
    if (i > 0) fm[line.slice(0, i).trim()] = line.slice(i + 1).trim();
  }
  return { fm, body: m[2] };
}

const loadConcepts = () => ls(DIRS.concepts).filter(f => f.endsWith('.md')).map(f => {
  const { fm, body } = parseMd(read(join(DIRS.concepts, f)));
  const stage = Number(fm.stage || 0);
  const due = daysSince(fm.lastReview) >= LADDER[Math.min(stage, LADDER.length - 1)];
  return {
    slug: f.replace(/\.md$/, ''), title: fm.title || f, tags: (fm.tags || '').split(',').map(s => s.trim()).filter(Boolean),
    seen: Number(fm.seen || 1), stage, reviews: Number(fm.reviews || 0), shaky: Number(fm.shaky || 0),
    first: fm.first || '', last: fm.last || '', lastReview: fm.lastReview || 'never',
    entries: (fm.entries || '').split(',').map(s => s.trim()).filter(Boolean), due, body,
  };
});

const loadJournal = () => ls(DIRS.journal).filter(f => f.endsWith('.json'))
  .map(f => { try { return JSON.parse(read(join(DIRS.journal, f))); } catch { return null; } })
  .filter(Boolean).sort((a, b) => (b.date + b.ticket).localeCompare(a.date + a.ticket));

const loadLessons = () => ls(DIRS.lessons).filter(f => f.endsWith('.md') && f !== 'active-rules.md').map(f => {
  const { fm, body } = parseMd(read(join(DIRS.lessons, f)));
  return { slug: f.replace(/\.md$/, ''), destination: fm.destination || '?', status: fm.status || '?',
           outcome: fm.outcome || '', seen: Number(fm.seen || 1), source: fm.source || '', body };
});

function markReviewed(slug, result) {
  const f = join(DIRS.concepts, slug + '.md');
  if (!existsSync(f)) return { ok: false, error: 'no such concept' };
  let text = read(f);
  const { fm } = parseMd(text);
  let stage = Number(fm.stage || 0);
  stage = result === 'known' ? Math.min(stage + 1, LADDER.length - 1) : 0;
  const set = (k, v) => {
    text = new RegExp(`^${k}:.*$`, 'm').test(text)
      ? text.replace(new RegExp(`^${k}:.*$`, 'm'), `${k}: ${v}`)
      : text.replace(/^---\n/, `---\n${k}: ${v}\n`);
  };
  set('stage', stage);
  set('lastReview', today());
  set('reviews', Number(fm.reviews || 0) + 1);
  if (result === 'shaky') set('shaky', Number(fm.shaky || 0) + 1);
  writeFileSync(f, text);
  return { ok: true, stage, nextIn: LADDER[Math.min(stage, LADDER.length - 1)] };
}

const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

// Minimal markdown: headings, fenced code, inline code, bold, lists, paragraphs.
function md(src) {
  const out = []; let inCode = false, inList = false;
  for (const raw of String(src).split('\n')) {
    if (raw.startsWith('```')) {
      if (inList) { out.push('</ul>'); inList = false; }
      out.push(inCode ? '</code></pre>' : `<pre class="code"><code>`); inCode = !inCode; continue;
    }
    if (inCode) { out.push(esc(raw)); continue; }
    const line = esc(raw);
    const inline = t => t.replace(/`([^`]+)`/g, '<code>$1</code>').replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
    const h = line.match(/^(#{1,4})\s+(.*)$/);
    if (h) { if (inList) { out.push('</ul>'); inList = false; } out.push(`<h${h[1].length + 2}>${inline(h[2])}</h${h[1].length + 2}>`); continue; }
    const li = line.match(/^\s*(?:[-*]|\d+\.)\s+(.*)$/);
    if (li) { if (!inList) { out.push('<ul>'); inList = true; } out.push(`<li>${inline(li[1])}</li>`); continue; }
    if (!line.trim()) { if (inList) { out.push('</ul>'); inList = false; } continue; }
    if (inList) { out.push('</ul>'); inList = false; }
    out.push(`<p>${inline(line)}</p>`);
  }
  if (inList) out.push('</ul>');
  if (inCode) out.push('</code></pre>');
  return out.join('\n');
}

function page() {
  const concepts = loadConcepts(), journal = loadJournal(), lessons = loadLessons();
  const data = esc(JSON.stringify({ concepts, journal, lessons, today: today() }));
  return `<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Learning dashboard</title>
<style>
:root{--bg:#fbfaf8;--panel:#fff;--ink:#1c1b19;--muted:#6b6862;--line:#e6e2db;--accent:#9a5b3d;--ok:#3d6b4a;--warn:#8a6d1f;--code:#f4f1ec}
@media (prefers-color-scheme:dark){:root{--bg:#16150f;--panel:#1e1d17;--ink:#eceae4;--muted:#9b978e;--line:#32302a;--accent:#d79b76;--ok:#8fc29c;--warn:#ddc37a;--code:#13120e}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.6 ui-sans-serif,-apple-system,"Segoe UI",sans-serif}
header{padding:20px 24px 0;max-width:1180px;margin:0 auto}
h1{font-size:19px;margin:0 0 2px;letter-spacing:-.01em}.sub{color:var(--muted);font-size:13px;margin:0 0 14px}
nav{display:flex;gap:4px;flex-wrap:wrap;border-bottom:1px solid var(--line)}
nav button{background:none;border:0;border-bottom:2px solid transparent;color:var(--muted);padding:8px 12px;cursor:pointer;font:inherit;font-size:13px}
nav button[aria-selected=true]{color:var(--ink);border-bottom-color:var(--accent);font-weight:600}
main{max-width:1180px;margin:0 auto;padding:18px 24px 64px}
.card{background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:14px 16px;margin-bottom:10px}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(260px,1fr));gap:10px}
.row{display:flex;gap:10px;align-items:baseline;flex-wrap:wrap}
.tag{font-size:11px;color:var(--muted);border:1px solid var(--line);border-radius:999px;padding:1px 8px}
.pill{font-size:11px;border-radius:999px;padding:1px 8px;border:1px solid var(--line)}
.due{color:var(--warn);border-color:var(--warn)}.known{color:var(--ok);border-color:var(--ok)}
.muted{color:var(--muted);font-size:13px}.date{font-variant-numeric:tabular-nums;color:var(--muted);font-size:12px}
h2{font-size:15px;margin:22px 0 8px}h3,h4,h5{font-size:14px;margin:14px 0 4px}
pre.code{background:var(--code);border:1px solid var(--line);border-radius:8px;padding:10px 12px;overflow-x:auto;font-size:12.5px;line-height:1.5}
code{background:var(--code);padding:1px 5px;border-radius:4px;font-size:12.5px}
pre.code code{background:none;padding:0}
button.act{font:inherit;font-size:13px;padding:6px 12px;border-radius:7px;border:1px solid var(--line);background:var(--panel);color:var(--ink);cursor:pointer}
button.act:hover{border-color:var(--accent)}
.hide{display:none}.stat{font-size:26px;font-weight:600;letter-spacing:-.02em}
input[type=search]{font:inherit;font-size:13px;padding:6px 10px;border-radius:7px;border:1px solid var(--line);background:var(--panel);color:var(--ink);width:240px}
details>summary{cursor:pointer;color:var(--muted);font-size:13px}
</style></head><body>
<header><h1>Learning dashboard</h1><p class="sub" id="sub"></p>
<nav id="tabs"></nav></header><main id="view"></main>
<script id="data" type="application/json">${data}</script>
<script>
const D=JSON.parse(document.getElementById('data').textContent);
const $=(h)=>{const d=document.createElement('div');d.innerHTML=h;return d};
const view=document.getElementById('view'),tabs=document.getElementById('tabs');
const TABS=['Revision','Timeline','Concepts','Lessons','Stats'];let cur='Revision',q='';
document.getElementById('sub').textContent=
  D.journal.length+' entries · '+D.concepts.length+' concepts · '+
  D.concepts.filter(c=>c.due).length+' due today · '+D.lessons.length+' lessons';
function esc(s){return String(s??'').replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]))}
function render(){
  tabs.innerHTML=TABS.map(t=>'<button aria-selected="'+(t===cur)+'">'+t+(t==='Revision'&&D.concepts.filter(c=>c.due).length?' ('+D.concepts.filter(c=>c.due).length+')':'')+'</button>').join('');
  [...tabs.children].forEach(b=>b.onclick=()=>{cur=b.textContent.replace(/ \\(\\d+\\)$/,'');render()});
  view.innerHTML='';
  ({Revision:revision,Timeline:timeline,Concepts:library,Lessons:lessonView,Stats:stats})[cur]();
}
function revision(){
  const due=D.concepts.filter(c=>c.due).sort((a,b)=>b.seen-a.seen);
  if(!due.length){view.append($('<div class="card"><p class="muted">Nothing due. The ladder is clear — come back when a concept comes round again.</p></div>').firstChild);return}
  view.append($('<p class="muted">Answer before you reveal. Honest "shaky" is what makes the schedule work — it resets the interval to one day.</p>').firstChild);
  for(const c of due){
    const qm=(c.body.match(/^Q:\\s*(.*)$/m)||[])[1]||'What is the core mechanism here, and when does it bite?';
    const el=$('<div class="card"><div class="row"><strong>'+esc(c.title)+'</strong>'+
      c.tags.map(t=>'<span class="tag">'+esc(t)+'</span>').join('')+
      '<span class="tag">seen '+c.seen+'</span><span class="pill due">stage '+c.stage+'</span></div>'+
      '<p style="margin:10px 0 6px"><strong>'+esc(qm)+'</strong></p>'+
      '<div class="hide answer">'+window.MD(c.body)+'</div>'+
      '<div class="row" style="margin-top:10px"><button class="act reveal">Reveal</button>'+
      '<button class="act known hide">I know this</button><button class="act shaky hide">Shaky</button></div></div>').firstChild;
    el.querySelector('.reveal').onclick=()=>{el.querySelector('.answer').classList.remove('hide');
      el.querySelector('.reveal').classList.add('hide');
      el.querySelector('.known').classList.remove('hide');el.querySelector('.shaky').classList.remove('hide')};
    for(const r of ['known','shaky'])el.querySelector('.'+r).onclick=async()=>{
      const res=await fetch('/api/review',{method:'POST',headers:{'content-type':'application/json'},
        body:JSON.stringify({slug:c.slug,result:r})}).then(x=>x.json());
      c.due=false;el.innerHTML='<p class="muted">'+esc(c.title)+' — '+r+', next in '+res.nextIn+' day(s).</p>'};
    view.append(el)
  }
}
function timeline(){
  const by={};for(const e of D.journal)(by[e.date]=by[e.date]||[]).push(e);
  const days=Object.keys(by).sort().reverse();
  if(!days.length){view.append($('<div class="card"><p class="muted">No entries yet. They appear automatically when a run starts.</p></div>').firstChild);return}
  for(const d of days){
    view.append($('<h2>'+d+'</h2>').firstChild);
    for(const e of by[d]) view.append($('<div class="card"><div class="row"><span class="pill">'+esc(e.track)+'</span>'+
      '<strong>'+esc(e.ticket)+'</strong> '+esc(e.title||'')+'<span class="tag">'+esc(e.repo)+'</span></div>'+
      (e.summary?'<p>'+esc(e.summary)+'</p>':'')+
      (e.areas||[]).map(a=>'<span class="tag">'+esc(a)+'</span>').join(' ')+
      ((e.concepts||[]).length?'<p class="muted" style="margin-top:8px">learned: '+e.concepts.map(esc).join(', ')+'</p>':'')+
      ((e.prs||[]).length?'<p class="muted">'+e.prs.map(p=>'<a href="'+esc(p)+'">'+esc(p.split('/').pop())+'</a>').join(' · ')+'</p>':'')+
      '</div>').firstChild)
  }
}
function library(){
  const bar=$('<div class="row" style="margin-bottom:12px"><input type="search" placeholder="filter concepts…"></div>').firstChild;
  const inp=bar.querySelector('input');inp.value=q;inp.oninput=()=>{q=inp.value;render();setTimeout(()=>{const i=view.querySelector('input');i&&i.focus()})};
  view.append(bar);
  const list=D.concepts.filter(c=>!q||(c.title+c.slug+c.tags.join()+c.body).toLowerCase().includes(q.toLowerCase()))
    .sort((a,b)=>b.seen-a.seen||a.title.localeCompare(b.title));
  const g=$('<div class="grid"></div>').firstChild;
  for(const c of list)g.append($('<div class="card"><div class="row"><strong>'+esc(c.title)+'</strong></div>'+
    '<div class="row" style="margin:6px 0">'+c.tags.map(t=>'<span class="tag">'+esc(t)+'</span>').join('')+
    '<span class="tag">seen '+c.seen+'</span><span class="pill '+(c.due?'due':'known')+'">'+(c.due?'due':'stage '+c.stage)+'</span></div>'+
    '<details><summary>open</summary>'+window.MD(c.body)+
    '<p class="muted">first '+esc(c.first)+' · last '+esc(c.last)+' · reviews '+c.reviews+(c.shaky?' · shaky '+c.shaky:'')+'</p></details></div>').firstChild);
  view.append(g)
}
function lessonView(){
  if(!D.lessons.length){view.append($('<div class="card"><p class="muted">No lessons yet.</p></div>').firstChild);return}
  for(const l of D.lessons)view.append($('<div class="card"><div class="row"><strong>'+esc(l.slug)+'</strong>'+
    '<span class="tag">'+esc(l.destination)+'</span><span class="pill '+(l.status==='applied'?'known':'due')+'">'+esc(l.status)+'</span>'+
    (l.outcome?'<span class="tag">'+esc(l.outcome)+'</span>':'')+'<span class="tag">seen '+l.seen+'</span></div>'+
    '<details><summary>open</summary>'+window.MD(l.body)+'</details></div>').firstChild)
}
function stats(){
  const byTrack={},byTag={},byWeek={};
  for(const e of D.journal){byTrack[e.track]=(byTrack[e.track]||0)+1;
    const w=e.date.slice(0,7);byWeek[w]=(byWeek[w]||0)+1}
  for(const c of D.concepts)for(const t of c.tags)byTag[t]=(byTag[t]||0)+1;
  const box=(l,v)=>'<div class="card"><div class="stat">'+v+'</div><div class="muted">'+l+'</div></div>';
  view.append($('<div class="grid">'+box('runs',D.journal.length)+box('concepts',D.concepts.length)+
    box('due today',D.concepts.filter(c=>c.due).length)+box('rules learned',D.lessons.filter(l=>l.status==='applied').length)+'</div>').firstChild);
  const tbl=(t,o)=>'<h2>'+t+'</h2><div class="card">'+(Object.keys(o).length?Object.entries(o).sort((a,b)=>b[1]-a[1])
    .map(([k,v])=>'<div class="row"><span style="width:200px">'+esc(k)+'</span><span class="muted">'+v+'</span></div>').join(''):'<p class="muted">nothing yet</p>')+'</div>';
  view.append($(tbl('by track',byTrack)+tbl('by month',byWeek)+tbl('concepts by tag',byTag)).firstChild.parentNode)
}
window.MD=${md.toString().replace(/esc\(/g,'esc(')};
render();
</script></body></html>`;
}

const srv = createServer((req, res) => {
  if (req.method === 'POST' && req.url === '/api/review') {
    let b = ''; req.on('data', c => b += c);
    req.on('end', () => {
      let out; try { const { slug, result } = JSON.parse(b); out = markReviewed(slug, result); }
      catch (e) { out = { ok: false, error: String(e) }; }
      res.writeHead(out.ok ? 200 : 400, { 'content-type': 'application/json' }); res.end(JSON.stringify(out));
    });
    return;
  }
  res.writeHead(200, { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store' });
  res.end(page());   // rebuilt per request: the ledger is the source of truth, not a build artifact
});

srv.listen(port, () => {
  console.log(`learning dashboard  http://localhost:${port}`);
  console.log(`  reading ${root}`);
  const c = loadConcepts();
  console.log(`  ${loadJournal().length} entries · ${c.length} concepts · ${c.filter(x => x.due).length} due today`);
});
