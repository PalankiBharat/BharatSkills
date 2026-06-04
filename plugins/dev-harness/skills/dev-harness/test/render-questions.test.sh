#!/usr/bin/env bash
# render-questions.sh turns a structured questions.json into a clean HTML form:
# severity groups, recommended options, radio/text fields, a parseable Copy-answers block.
. "$(dirname "$0")/_assert.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"
T="$(mktemp -d)"; export HARNESS_ROOT="$T/.harness"; mkdir -p "$HARNESS_ROOT/artifacts"
Q="$HARNESS_ROOT/artifacts/questions.json"
cat > "$Q" <<'JSON'
{
  "title": "Two blockers before Dev.",
  "groups": [
    { "label": "Blockers", "severity": "blocker", "questions": [
      { "id": "b1", "type": "single",
        "q": "SPEC.md is missing. How do we proceed?",
        "why": "Sole source of truth for the layout.",
        "options": [
          {"label": "I'll paste it now", "recommended": true},
          {"label": "Use a default"} ],
        "allowNote": true },
      { "id": "b2", "type": "text", "q": "Paste the spec." } ] },
    { "label": "Clarifications", "severity": "clarification", "questions": [
      { "id": "c1", "type": "single", "q": "Skip malformed rows?",
        "options": [ {"label":"Skip","recommended":true}, {"label":"Fail"} ] } ] }
  ]
}
JSON

OUT="$(bash "$HERE/../scripts/render-questions.sh" "$Q" --no-open)"
assert_file "$OUT"
body="$(cat "$OUT")"
# the structured data is embedded, and the form chrome is present
assert_contains "$body" "SPEC.md is missing"
assert_contains "$body" "grp-blocker"
assert_contains "$body" "grp-clarification"
assert_contains "$body" "Recommended"
assert_contains "$body" "Copy answers"
assert_contains "$body" "HARNESS ANSWERS"
# exactly two real </script> tags (no breakout from the embedded JSON)
assert_eq "$(grep -c '</script>' "$OUT")" "2"
# the embedded Q is valid JSON
python3 -c "import re,json,sys; m=re.search(r'const Q=(.*?);</script>', open('$OUT').read(), re.S); json.loads(m.group(1))" \
  || _FAIL "embedded Q is not valid JSON"
# invalid input is rejected
echo '{ not json' > "$T/bad.json"
( bash "$HERE/../scripts/render-questions.sh" "$T/bad.json" --no-open 2>/dev/null ) && _FAIL "should reject invalid JSON"

# optional: functionally run the builder in node if available (build the real DOM)
if command -v node >/dev/null 2>&1; then
  node - "$OUT" <<'NODE' || _FAIL "builder JS failed functional run"
const fs=require('fs'),html=fs.readFileSync(process.argv[2],'utf8');
const s=[...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].map(m=>m[1]);
function mk(){return {className:'',children:[],dataset:{},attrs:{},_html:'',appendChild(c){this.children.push(c);return c},
 set innerHTML(v){this._html=v},get innerHTML(){return this._html},set type(v){this.attrs.type=v},get type(){return this.attrs.type},
 set name(v){},set value(v){this.attrs.value=v},get value(){return ''},set checked(v){},set placeholder(v){},set hidden(v){},set id(v){},set onclick(f){},
 querySelector(){return null},querySelectorAll(){return []}};}
const app=mk();const document={getElementById:()=>app,createElement:mk};
const Q=JSON.parse(html.match(/const Q=([\s\S]*?);<\/script>/)[1]);
new Function('Q','document','navigator','getSelection',s[1])(Q,document,{clipboard:null},()=>({removeAllRanges(){},addRange(){}}));
let cards=0,rec=0,radios=0;(function w(n){if(n.dataset&&n.dataset.qid)cards++;if(n._html&&/Recommended/.test(n._html))rec++;if(n.attrs&&n.attrs.type==='radio')radios++;(n.children||[]).forEach(w);})(app);
if(cards!==3||rec!==2||radios!==4){console.error('cards='+cards+' rec='+rec+' radios='+radios);process.exit(1);}
NODE
fi
echo OK
