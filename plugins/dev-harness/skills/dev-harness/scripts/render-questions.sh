#!/usr/bin/env bash
# render-questions.sh <questions.json> [--no-open]
# Render a STRUCTURED questionnaire (not a wall of prose) as a clean, minimal HTML form:
# grouped by severity, one field per question (radio / checkbox / text), the recommended
# option pre-selected and badged, and a single "Copy answers" button that emits a tidy,
# parseable reply block. The schema lives in references/html-interaction.md.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/lib.sh"
ROOT="${HARNESS_ROOT:-$(git rev-parse --show-toplevel)/.harness}"
THEME="$HERE/../assets/theme.css"

JSON_FILE="${1:?usage: render-questions.sh <questions.json> [--no-open]}"; OPEN=1
[ "${2:-}" = "--no-open" ] && OPEN=0
[ -f "$JSON_FILE" ] || { echo "no questions file: $JSON_FILE" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "jq required" >&2; exit 3; }
jq -e . "$JSON_FILE" >/dev/null 2>&1 || { echo "invalid JSON: $JSON_FILE" >&2; exit 4; }

mkdir -p "$ROOT/review"
OUT="$ROOT/review/questions-$(date +%Y%m%d-%H%M%S).html"
# Redact secrets, compact, and neutralize any </script> breakout (escape < > inside strings).
DATA="$(redact_secrets < "$JSON_FILE" | jq -c . | sed -e 's,<,\\u003c,g' -e 's,>,\\u003e,g')"
CSS="$(cat "$THEME" 2>/dev/null || true)"

read -r -d '' FORMCSS <<'CSS' || true
.grp{margin-top:26px}
.grp-h{display:inline-flex;align-items:center;gap:8px;font:700 12px/1 var(--mono);text-transform:uppercase;
  letter-spacing:.07em;padding:7px 12px;border-radius:999px;margin-bottom:4px}
.grp-blocker .grp-h{color:var(--red);background:rgba(248,113,113,.10);border:1px solid rgba(248,113,113,.30)}
.grp-clarification .grp-h{color:var(--amber);background:rgba(251,191,36,.10);border:1px solid rgba(251,191,36,.28)}
.q{background:var(--bg-surface);border:1px solid var(--border);border-radius:var(--r-lg);padding:18px 20px;margin-top:14px}
.q-n{color:var(--text-tertiary);font:700 12px/1 var(--mono)}
.q-t{font-size:16px;font-weight:650;margin:2px 0 4px;letter-spacing:-.01em}
.q-why{color:var(--text-secondary);font-size:13.5px;line-height:1.55;margin-bottom:13px}
.opt{display:flex;align-items:flex-start;gap:11px;background:var(--bg-input);border:1px solid var(--border);
  border-radius:var(--r-md);padding:11px 14px;margin-top:8px;cursor:pointer;transition:border-color .12s,background .12s}
.opt:hover{border-color:var(--border-hover)}
.opt.rec{border-color:var(--accent-border);background:var(--accent-bg)}
.opt input{margin-top:3px;accent-color:var(--accent);width:16px;height:16px;flex:none}
.opt-l{font-size:14.5px;line-height:1.5}
.badge{display:inline-block;margin-left:8px;color:var(--accent);background:rgba(139,92,246,.12);
  border:1px solid var(--accent-border);border-radius:999px;font:600 10px/1 var(--mono);
  text-transform:uppercase;letter-spacing:.06em;padding:4px 8px;vertical-align:middle}
.q textarea{width:100%;min-height:72px;margin-top:10px;background:var(--bg-input);color:var(--text);
  border:1px solid var(--border);border-radius:var(--r-md);padding:11px 13px;font:14px/1.6 var(--font);resize:vertical}
.q textarea:focus{outline:none;border-color:var(--accent-border);box-shadow:0 0 0 3px var(--accent-bg)}
.note-l{display:block;color:var(--text-tertiary);font:600 10px/1 var(--mono);text-transform:uppercase;
  letter-spacing:.07em;margin-top:12px}
.bar{position:sticky;bottom:0;display:flex;align-items:center;gap:14px;margin-top:28px;padding:16px 0;
  background:linear-gradient(transparent,var(--bg-root) 28%)}
.bar button{background:var(--accent);color:#fff;border:0;border-radius:var(--r-md);padding:12px 20px;
  font:650 14px/1 var(--font);cursor:pointer;transition:background .12s}
.bar button:hover{background:var(--accent-hover)}
.bar #s{color:var(--green);font:600 13px/1 var(--font)}
#pv{white-space:pre-wrap;background:var(--bg-surface);border:1px solid var(--border);border-radius:var(--r-md);
  padding:14px;margin-top:14px;font:13px/1.6 var(--mono);color:#dfe0ea}
CSS

read -r -d '' JS <<'JS' || true
var app=document.getElementById('app');
function E(t,c,h){var e=document.createElement(t);if(c)e.className=c;if(h!=null)e.innerHTML=h;return e;}
function esc(s){return String(s==null?'':s).replace(/[&<>"]/g,function(m){return{'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[m];});}
var head=E('header');head.appendChild(E('h1',null,'dev<span class="dot">·</span>harness'));
head.appendChild(E('span','kind','questions'));app.appendChild(head);
if(Q.title)app.appendChild(E('p','q-why',esc(Q.title)));
var n=0;
(Q.groups||[]).forEach(function(g){
  var sev=(g.severity==='blocker')?'blocker':'clarification';
  var sec=E('section','grp grp-'+sev);
  sec.appendChild(E('div','grp-h',(sev==='blocker'?'🔴 ':'🟡 ')+esc(g.label||sev)));
  (g.questions||[]).forEach(function(q){
    n++;var card=E('div','q');card.dataset.qid=q.id;card.dataset.qtype=q.type||'single';
    card.appendChild(E('div','q-n','Q'+n));
    card.appendChild(E('div','q-t',esc(q.q)));
    if(q.why)card.appendChild(E('div','q-why',esc(q.why)));
    if((q.type||'single')==='text'){
      var ta=E('textarea');ta.dataset.ans=q.id;ta.placeholder='Type your answer…';card.appendChild(ta);
    }else{
      var multi=(q.type==='multi');
      (q.options||[]).forEach(function(o){
        var lab=E('label','opt'+(o.recommended?' rec':''));
        var inp=E('input');inp.type=multi?'checkbox':'radio';inp.name=q.id;inp.value=o.label;inp.dataset.ans=q.id;
        if(o.recommended&&!multi)inp.checked=true;
        lab.appendChild(inp);
        lab.appendChild(E('span','opt-l',esc(o.label)+(o.recommended?'<span class="badge">Recommended</span>':'')));
        card.appendChild(lab);
      });
      if(q.allowNote){card.appendChild(E('span','note-l','Optional note'));
        var nt=E('textarea');nt.dataset.note=q.id;nt.placeholder='Add detail if needed…';card.appendChild(nt);}
    }
    sec.appendChild(card);
  });
  app.appendChild(sec);
});
var bar=E('div','bar');var btn=E('button',null,'📋 Copy answers');var st=E('span');st.id='s';
bar.appendChild(btn);bar.appendChild(st);app.appendChild(bar);
var pv=E('pre');pv.id='pv';pv.hidden=true;app.appendChild(pv);
function collect(){
  var out=['HARNESS ANSWERS'];
  app.querySelectorAll('.q').forEach(function(card){
    var id=card.dataset.qid,type=card.dataset.qtype,ans=[];
    if(type==='text'){var t=card.querySelector('textarea[data-ans]');if(t&&t.value.trim())ans.push(t.value.trim());}
    else{card.querySelectorAll('input[data-ans]:checked').forEach(function(i){ans.push(i.value);});}
    out.push('['+id+'] '+(ans.length?ans.join(' | '):'(no answer)'));
    var note=card.querySelector('textarea[data-note]');
    if(note&&note.value.trim())out.push('  ['+id+' note] '+note.value.trim());
  });
  return out.join('\n');
}
btn.onclick=function(){var t=collect();
  if(navigator.clipboard&&navigator.clipboard.writeText){
    navigator.clipboard.writeText(t).then(function(){st.textContent='✓ copied — paste to Claude';},fallback);
  }else fallback();
  function fallback(){pv.hidden=false;pv.textContent=t;var r=document.createRange();r.selectNodeContents(pv);
    var s=getSelection();s.removeAllRanges();s.addRange(r);st.textContent='press ⌘C to copy';}
};
JS

{
  printf '<!DOCTYPE html><html lang="en"><head><meta charset="utf-8">'
  printf '<meta name="viewport" content="width=device-width, initial-scale=1">'
  printf '<title>dev-harness — questions</title><style>%s\n%s</style></head><body>' "$CSS" "$FORMCSS"
  printf '<div class="wrap" id="app"></div>'
  printf '<script>const Q=%s;</script>' "$DATA"
  printf '<script>%s</script>' "$JS"
  printf '</body></html>'
} > "$OUT"

if [ "$OPEN" -eq 1 ] && command -v open >/dev/null 2>&1; then open "$OUT" || true; fi
echo "$OUT"
