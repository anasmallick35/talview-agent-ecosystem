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
    question: questionOf(body),
  };
});

// A question wraps across lines in the source. `.` stops at the first newline, so a
// single-line capture truncates it mid-sentence. Read to a blank line, a Refs: line or
// the end. Derived HERE rather than in the browser so a test can assert on the value
// without rendering a page — the bug that shipped was invisible to every grep-the-HTML
// check, because the full body is embedded either way.
function questionOf(body) {
  // No /m flag: with it, `$` matches end of LINE, so the lazy match satisfied the
  // lookahead at the first newline and every question was truncated to one line.
  // Anchor the start with (?:^|\n) instead and let `$` mean end of string.
  const m = String(body).match(/(?:^|\n)Q:\s*([\s\S]*?)(?=\n\s*\n|\nRefs:|$)/);
  return (m ? m[1] : 'What is the core mechanism here, and when does it bite?')
    .replace(/\s*\n\s*/g, ' ').trim();
}

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
  // Source is hard-wrapped at ~80 columns. Treating every source line as its own
  // paragraph split sentences mid-clause and left orphan words on their own lines —
  // so consecutive non-blank lines are joined, as markdown intends.
  const out = []; let inCode = false, inList = false, para = [];
  const inline = t => t
    .replace(/`([^`]+)`/g, '<code>$1</code>')
    .replace(/\*\*([^*]+)\*\*/g, '<b>$1</b>')
    .replace(/(^|[\s(])\*([^*\s][^*]*)\*(?=[\s.,;:)]|$)/g, '$1<em>$2</em>');
  const flush = () => { if (para.length) { out.push('<p>' + inline(para.join(' ')) + '</p>'); para = []; } };
  const closeList = () => { if (inList) { out.push('</ul>'); inList = false; } };

  for (const raw of String(src).split('\n')) {
    if (raw.startsWith('```')) {
      flush(); closeList();
      out.push(inCode ? '</code></pre>' : '<pre class="code"><code>'); inCode = !inCode; continue;
    }
    if (inCode) { out.push(esc(raw)); continue; }
    const line = esc(raw);
    const h = line.match(/^(#{1,4})\s+(.*)$/);
    if (h) { flush(); closeList(); out.push('<h4>' + inline(h[2]) + '</h4>'); continue; }
    const li = line.match(/^\s*(?:[-*]|\d+\.)\s+(.*)$/);
    if (li) { flush(); if (!inList) { out.push('<ul>'); inList = true; } out.push('<li>' + inline(li[1]) + '</li>'); continue; }
    if (!line.trim()) { flush(); closeList(); continue; }
    // A continuation line inside a list item belongs to that item, not a new paragraph.
    if (inList && /^\s{2,}\S/.test(raw)) { out[out.length - 1] = out[out.length - 1].replace(/<\/li>$/, ' ' + inline(line.trim()) + '</li>'); continue; }
    closeList(); para.push(line.trim());
  }
  flush(); closeList();
  if (inCode) out.push('</code></pre>');
  return out.join('\n');
}

function inlineMd(s) {
  return esc(s).replace(/`([^`]+)`/g, '<code>$1</code>').replace(/\*\*([^*]+)\*\*/g, '<b>$1</b>');
}

function page() {
  const concepts = loadConcepts(), journal = loadJournal(), lessons = loadLessons();
  // NOT html-escaped. Entities are not decoded inside <script>, whose content is raw
  // text, so `&quot;` would reach JSON.parse literally and fail at position 1 — a blank
  // page with one console error. Escaping `<` as \u003c is valid JSON, cannot form
  // `</script>`, and needs no decoding. U+2028/9 are legal in JSON but not in JS strings.
  const data = JSON.stringify({ concepts, journal, lessons, today: today() })
    .replace(/</g, '\\u003c').replace(/\u2028/g, '\\u2028').replace(/\u2029/g, '\\u2029');
  const due = concepts.filter(c => c.due).length;

  return `<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Logbook</title>
<style>
/* Ink on paper. A logbook, not an analytics product: no charts, no stat tiles, no
   cards-for-everything. Structure comes from rules and rails, which carry meaning —
   a date rail IS the chronology, not decoration around it. */
:root{
  --paper:#f7f7f4; --raised:#fff; --ink:#16181d; --ink-soft:#575b64; --ink-faint:#8b8f98;
  --rule:#e2e2db; --rule-firm:#cfcfc6; --accent:#2743c9; --fading:#9a6b16; --held:#2f6b5e;
  --mark:#f0eee4;
  --serif:"Iowan Old Style",Palatino,"Palatino Linotype","Book Antiqua",Georgia,serif;
  --sans:ui-sans-serif,-apple-system,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;
  --mono:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;
}
@media (prefers-color-scheme:dark){:root{
  --paper:#121419; --raised:#171a20; --ink:#e8e9ec; --ink-soft:#a2a7b2; --ink-faint:#71767f;
  --rule:#272a31; --rule-firm:#363a43; --accent:#8ba0ff; --fading:#c9a24a; --held:#67b39e;
  --mark:#1d2027;
}}
*{box-sizing:border-box}
html{-webkit-text-size-adjust:100%}
body{margin:0;background:var(--paper);color:var(--ink);font:400 15px/1.55 var(--sans);
  font-variant-numeric:tabular-nums}
.wrap{max-width:1080px;margin:0 auto;padding:0 28px}

/* ── masthead ─────────────────────────────────────────────────────────────── */
header{padding:40px 0 0}
/* The hero is a sentence, not a number: the state of your memory is the thing this
   page exists to tell you, and it reads better as prose than as a tile. */
.state{font:400 clamp(26px,3.6vw,38px)/1.22 var(--serif);margin:0 0 6px;max-width:22ch;
  letter-spacing:-.01em}
.state b{font-weight:600;font-style:normal;color:var(--fading)}
.state .ok{color:var(--held)}
.state-sub{color:var(--ink-soft);font-size:14px;margin:0 0 26px;max-width:58ch}
nav{display:flex;gap:26px;border-bottom:1px solid var(--rule-firm);margin-bottom:2px}
nav button{appearance:none;background:none;border:0;padding:0 0 10px;margin:0;cursor:pointer;
  font:500 14px/1 var(--sans);color:var(--ink-faint);position:relative}
nav button:hover{color:var(--ink)}
nav button[aria-current=true]{color:var(--ink)}
nav button[aria-current=true]::after{content:"";position:absolute;left:0;right:0;bottom:-1px;
  height:2px;background:var(--accent)}
nav .count{font:500 11px/1 var(--mono);color:var(--fading);margin-left:5px}
main{padding:28px 0 90px;min-height:50vh}

/* ── timeline: a date rail, single-line rows ──────────────────────────────── */
.day{display:grid;grid-template-columns:92px 1fr;gap:0 20px;border-top:1px solid var(--rule)}
.day:first-child{border-top:0}
.day-date{font:500 12px/1.4 var(--mono);color:var(--ink-faint);padding:14px 0 0;
  position:sticky;top:0;align-self:start}
.day-rows{padding:6px 0 14px}
.row{display:flex;gap:11px;align-items:baseline;padding:7px 0;border-bottom:1px dotted var(--rule)}
.row:last-child{border-bottom:0}
.track{font:500 11px/1 var(--mono);color:var(--ink-faint);width:34px;flex:none;
  padding-top:2px;white-space:nowrap}
.track.bug{color:var(--fading)} .track.feature{color:var(--accent)} .track.tech_debt{color:var(--held)}
.row-id{font:500 13px/1.4 var(--mono);flex:none}
.row-id a{color:inherit;text-decoration:none;border-bottom:1px solid var(--rule-firm)}
.row-id a:hover{border-bottom-color:var(--accent);color:var(--accent)}
.row-title{color:var(--ink-soft);font-size:14px}
.row-learned{display:block;font-size:12.5px;color:var(--ink-faint);
  margin:-4px 0 8px 45px;padding-left:12px;border-left:2px solid var(--rule)}
.row-learned i{font-style:normal;border-bottom:1px solid var(--rule-firm)}

/* ── revision: one at a time ──────────────────────────────────────────────── */
.deck{max-width:660px}
.deck-pos{font:500 12px/1 var(--mono);color:var(--ink-faint);margin-bottom:18px}
.q{font:400 clamp(20px,2.4vw,25px)/1.4 var(--serif);margin:0 0 4px}
.q code{font:400 .82em/1 var(--mono);background:var(--mark);padding:3px 6px;border-radius:3px}
.q-meta{color:var(--ink-faint);font-size:13px;margin:10px 0 24px}
.q-meta span+span::before{content:"/";margin:0 7px;color:var(--rule-firm)}
.answer{border-top:1px solid var(--rule);padding-top:18px;margin-top:4px}
.acts{display:flex;gap:10px;margin-top:26px;flex-wrap:wrap}
button.act{appearance:none;font:500 14px/1 var(--sans);padding:10px 16px;border-radius:3px;
  border:1px solid var(--rule-firm);background:var(--raised);color:var(--ink);cursor:pointer}
button.act:hover{border-color:var(--ink-soft)}
button.act.primary{background:var(--ink);color:var(--paper);border-color:var(--ink)}
button.act.primary:hover{background:var(--accent);border-color:var(--accent)}
button.act.held:hover{border-color:var(--held);color:var(--held)}
button.act.fading:hover{border-color:var(--fading);color:var(--fading)}

/* ── reading: concepts and lessons ────────────────────────────────────────── */
.list{border-top:1px solid var(--rule)}
.item{border-bottom:1px solid var(--rule)}
.item>summary{list-style:none;cursor:pointer;padding:14px 0;display:flex;gap:14px;
  align-items:baseline}
.item>summary::-webkit-details-marker{display:none}
.item>summary:hover .item-title{color:var(--accent)}
.item-title{font:500 15px/1.4 var(--sans);flex:1}
.item-meta{font:500 11px/1 var(--mono);color:var(--ink-faint);flex:none;padding-top:3px}
.item-meta .dot{display:inline-block;width:6px;height:6px;border-radius:50%;
  background:var(--held);margin-right:7px;vertical-align:1px}
.item-meta .dot.is-due{background:var(--fading)}
.prose{font:400 15.5px/1.68 var(--serif);max-width:68ch;padding:0 0 22px;color:var(--ink)}
.prose h4{font:600 13px/1.4 var(--sans);letter-spacing:.01em;color:var(--ink-faint);
  margin:22px 0 6px}
.prose h4:first-child{margin-top:0}
.prose p{margin:0 0 11px}
.prose ul{margin:0 0 11px;padding-left:19px}
.prose li{margin:0 0 5px}
.prose code{font:400 13px/1 var(--mono);background:var(--mark);padding:2px 5px;border-radius:3px}
pre.code{background:var(--mark);border:1px solid var(--rule);border-radius:4px;
  padding:12px 14px;overflow-x:auto;margin:0 0 12px}
pre.code code{font:400 12.5px/1.6 var(--mono);background:none;padding:0;white-space:pre}
.tags{font:500 11px/1 var(--mono);color:var(--ink-faint)}
.tags i{font-style:normal}
.tags i+i::before{content:"·";margin:0 5px;color:var(--rule-firm)}

/* ── ledger ───────────────────────────────────────────────────────────────── */
.ledger{width:100%;border-collapse:collapse;max-width:520px;margin:0 0 34px}
.ledger caption{text-align:left;font:600 13px/1.4 var(--sans);color:var(--ink-faint);
  padding:0 0 8px}
.ledger td{padding:7px 0;border-bottom:1px solid var(--rule);font-size:14px}
.ledger td+td{text-align:right;font:500 13px/1.4 var(--mono);color:var(--ink-soft);width:70px}

.search{font:400 14px/1 var(--sans);padding:9px 12px;border-radius:3px;
  border:1px solid var(--rule-firm);background:var(--raised);color:var(--ink);
  width:280px;margin-bottom:4px}
.search:focus{outline:2px solid var(--accent);outline-offset:1px;border-color:transparent}
.empty{font:400 17px/1.5 var(--serif);color:var(--ink-soft);max-width:46ch;padding:18px 0}
.empty code{font:400 13px/1 var(--mono);background:var(--mark);padding:2px 6px;border-radius:3px}
:focus-visible{outline:2px solid var(--accent);outline-offset:2px;border-radius:2px}
@media (max-width:620px){
  .day{grid-template-columns:1fr;gap:0}
  .day-date{position:static;padding:14px 0 2px}
  .row{flex-wrap:wrap}
  .row-learned{padding-left:0}
}
@media (prefers-reduced-motion:reduce){*{transition:none!important;animation:none!important}}
</style></head><body>
<div class="wrap">
  <header>
    <p class="state" id="state"></p>
    <p class="state-sub" id="state-sub"></p>
    <nav id="tabs"></nav>
  </header>
  <main id="view"></main>
</div>
<script id="data" type="application/json">${data}</script>
<script>
const D=JSON.parse(document.getElementById('data').textContent);
const view=document.getElementById('view'),tabs=document.getElementById('tabs');
const esc=s=>String(s??'').replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
const h=s=>{const t=document.createElement('template');t.innerHTML=s.trim();return t.content};
const TABS=[['Timeline',0],['Revision',1],['Concepts',0],['Lessons',0],['Stats',0]];
let cur='Timeline',q='',deck=0;
const dueList=()=>D.concepts.filter(c=>c.due).sort((a,b)=>b.seen-a.seen);
const TRACK={bug:'bug',feature:'feat',tech_debt:'debt',sentry:'sntry'};

function masthead(){
  const n=dueList().length,c=D.concepts.length;
  const el=document.getElementById('state'),sub=document.getElementById('state-sub');
  if(!c){el.innerHTML='Nothing recorded yet.';
    sub.innerHTML='Work shows up here on its own. Notes do not \\u2014 write one with <code>/tlv:concept</code> while the code is still in front of you.';return}
  el.innerHTML=n?'<b>'+n+'</b> '+(n===1?'concept is':'concepts are')+' fading.'
                :'<span class="ok">Nothing is fading today.</span>';
  sub.textContent=n?'Each one comes back further out when you hold it, and tomorrow when you do not.'
                   :c+' concept'+(c===1?'':'s')+' held. The next one is due when its interval runs out.';
}
function render(){
  tabs.innerHTML=TABS.map(([t,badge])=>'<button aria-current="'+(t===cur)+'">'+t+
    (badge&&dueList().length?'<span class="count">'+dueList().length+'</span>':'')+'</button>').join('');
  [...tabs.children].forEach(b=>b.onclick=()=>{cur=b.firstChild.textContent;render()});
  view.innerHTML='';masthead();
  ({Timeline:timeline,Revision:revision,Concepts:concepts,Lessons:lessons,Stats:stats})[cur]();
}
function empty(msg){view.append(h('<p class="empty">'+msg+'</p>'))}

function timeline(){
  if(!D.journal.length)return empty('No entries yet. One is written each time a run starts.');
  const by={};for(const e of D.journal)(by[e.date]=by[e.date]||[]).push(e);
  for(const d of Object.keys(by).sort().reverse()){
    const rows=by[d].map(e=>{
      const id=e.prs&&e.prs.length
        ? '<a href="'+esc(e.prs[0])+'" target="_blank" rel="noreferrer">'+esc(e.ticket)+'</a>'
        : esc(e.ticket);
      return '<div class="row"><span class="track '+esc(e.track)+'" title="'+esc(e.track.replace('_',' '))+'">'+
        esc(TRACK[e.track]||e.track.slice(0,4))+'</span>'+
        '<span class="row-id">'+id+'</span>'+
        (e.title?'<span class="row-title">'+esc(e.title)+'</span>':'')+'</div>'+
        ((e.concepts||[]).length?'<span class="row-learned">learned '+
          e.concepts.map(c=>'<i>'+esc(c)+'</i>').join(', ')+'</span>':'');
    }).join('');
    view.append(h('<section class="day"><div class="day-date">'+d+'</div><div class="day-rows">'+rows+'</div></section>'));
  }
}

function revision(){
  const list=dueList();
  if(!list.length)return empty('Nothing due. Concepts come back on their own \\u2014 1, 3, 7, 21 then 60 days.');
  if(deck>=list.length)deck=0;
  const c=list[deck];
  const el=h('<div class="deck">'+
    '<p class="deck-pos">'+(deck+1)+' of '+list.length+'</p>'+
    '<p class="q">'+inlineMd(c.question)+'</p>'+
    '<p class="q-meta"><span>'+esc(c.title)+'</span><span>met '+c.seen+'\\u00d7</span>'+
      (c.lastReview&&c.lastReview!=='never'?'<span>last seen '+esc(c.lastReview)+'</span>':'<span>never reviewed</span>')+'</p>'+
    '<div class="answer" hidden><div class="prose">'+
      window.MD(c.body.replace(/\\n##\\s*Revise with[\\s\\S]*$/,''))+'</div></div>'+
    '<div class="acts"><button class="act primary reveal">Show the answer</button></div></div>').firstElementChild;
  const acts=el.querySelector('.acts');
  el.querySelector('.reveal').onclick=()=>{
    el.querySelector('.answer').hidden=false;
    acts.innerHTML='<button class="act held" data-r="known">I had this</button>'+
                   '<button class="act fading" data-r="shaky">Not solid</button>';
    acts.querySelectorAll('button').forEach(b=>b.onclick=async()=>{
      const r=b.dataset.r;
      const res=await fetch('/api/review',{method:'POST',headers:{'content-type':'application/json'},
        body:JSON.stringify({slug:c.slug,result:r})}).then(x=>x.json()).catch(()=>({}));
      c.due=false;c.stage=res.stage??c.stage;c.lastReview=D.today;
      deck=0;render();
      view.prepend(h('<p class="deck-pos">'+esc(c.title)+' \\u2014 back in '+(res.nextIn??1)+' day'+((res.nextIn??1)===1?'':'s')+'</p>'));
    });
  };
  view.append(el);
}

function readingList(items,build){
  const frag=document.createElement('div');frag.className='list';
  for(const it of items)frag.append(h(build(it)));
  view.append(frag);
}
function concepts(){
  if(!D.concepts.length)return empty('No notes yet. Write one with <code>/tlv:concept</code> at the end of a piece of work.');
  const bar=h('<input class="search" type="search" placeholder="Filter notes" value="'+esc(q)+'">').firstElementChild;
  bar.oninput=()=>{q=bar.value;render();const i=view.querySelector('.search');if(i){i.focus();i.setSelectionRange(i.value.length,i.value.length)}};
  view.append(bar);
  const list=D.concepts.filter(c=>!q||(c.title+c.slug+c.tags.join()+c.body).toLowerCase().includes(q.toLowerCase()))
    .sort((a,b)=>b.seen-a.seen||a.title.localeCompare(b.title));
  if(!list.length)return empty('Nothing matches \\u201c'+esc(q)+'\\u201d.');
  readingList(list,c=>'<details class="item"><summary>'+
    '<span class="item-title">'+esc(c.title)+'</span>'+
    '<span class="item-meta"><span class="dot'+(c.due?' is-due':'')+'"></span>met '+c.seen+'\\u00d7</span></summary>'+
    '<div class="prose">'+window.MD(c.body)+'</div>'+
    '<p class="tags">'+c.tags.map(t=>'<i>'+esc(t)+'</i>').join('')+'</p></details>');
}
function lessons(){
  if(!D.lessons.length)return empty('No rules yet. They are written when review lands on a pull request.');
  readingList(D.lessons,l=>'<details class="item"><summary>'+
    '<span class="item-title">'+esc(l.slug)+'</span>'+
    '<span class="item-meta">'+esc(l.destination)+' \\u00b7 '+esc(l.status)+'</span></summary>'+
    '<div class="prose">'+window.MD(l.body)+'</div></details>');
}
function stats(){
  const byTrack={},byMonth={},byTag={};
  for(const e of D.journal){byTrack[e.track]=(byTrack[e.track]||0)+1;
    const m=e.date.slice(0,7);byMonth[m]=(byMonth[m]||0)+1}
  for(const c of D.concepts)for(const t of c.tags)byTag[t]=(byTag[t]||0)+1;
  const tbl=(cap,o,emptyMsg)=>'<table class="ledger"><caption>'+cap+'</caption><tbody>'+
    (Object.keys(o).length?Object.entries(o).sort((a,b)=>b[1]-a[1])
      .map(([k,v])=>'<tr><td>'+esc(k.replace('_',' '))+'</td><td>'+v+'</td></tr>').join('')
      :'<tr><td>'+emptyMsg+'</td><td>0</td></tr>')+'</tbody></table>';
  view.append(h(tbl('Runs by track',byTrack,'none yet')));
  view.append(h(tbl('Runs by month',byMonth,'none yet')));
  view.append(h(tbl('Notes by tag',byTag,'none yet')));
}
window.MD=${md.toString()};
const inlineMd=${inlineMd.toString()};
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
