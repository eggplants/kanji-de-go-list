#!/usr/bin/env bash

set -euo pipefail

LOG="${LOG:-}"
[[ -n "$LOG" ]] && echo Verbose LOG will not be printed.

SKIP="${SKIP:-}"
[[ -n "$SKIP" ]] && echo Processes of image conversion will be skipped.

if ! command -v awk convert mogrify jq ruby &>/dev/null
then
  echo "install: awk convert mogrify jq ruby" >&2
  exit 1
fi

if ! [[ -d '漢字でGO!' ]]
then
  echo "Download & Extract: <https://plicy.net/GamePlay/155561>" >&2
  exit 1
fi

echo "[TSV]"

< '漢字でGO!/www/data/CommonEvents.json' jq '
  .[]
  | select(. != null)
  | .list[]
  | select(.code == 122)
  | select(
      (.parameters[0] == .parameters[1])
      and ([.parameters[1]] | inside([9,10,19,20]))
      and (.parameters[2] == 0)
      and (.parameters[3] == 4)
      and ([.parameters[4]] | inside([0]) | not)
    )
  | .parameters[4]' -r |
  tr -d \" |
  sed -z 's/芲悧囧谿.0*.//' |
  ruby -e '
    puts STDIN.read
      .split(?\n)
      .each_slice(4)
      .map{[_2 != ?0 * 21 ? [_1, _2] * ?、 : _1, _3, _4].map(&:strip)}
      .map{_1 * ?\t}
      .filter{_1=~/\p{Hiragana}/}
  ' > _answer.tsv

find '漢字でGO!/www/img/pictures' -name 'Lv*' |
  grep -E 'Lv[0-9]+_[0-9]+.rpgmvp' |
  grep -v 0000 |
  awk -F/ '$0=$NF' | sort -V > _problem_a.tsv

find '漢字でGO!/www/img/pictures' -name 'LvCa004_*' |
  awk -F/ '$0=$NF' | sort -V > _problem_b.tsv

len_a="$(wc -l <_answer.tsv)"
len_b="$(wc -l <_problem_a.tsv)"
len_c="$(wc -l <_problem_b.tsv)"
if ! [[ "$len_a" == "$((len_b+len_c))" ]]
then
  echo "Error: _answer.tsv lines != _problem_a.tsv + _problem_b.tsv  mismatch.">&2
  exit 1
fi

echo "problem	answer	line1	line2" > kanji_de_go.tsv
paste <(cat _problem_a.tsv _problem_b.tsv) _answer.tsv | sed 's/.rpgmvp//' >> kanji_de_go.tsv

mkdir -p ./kanji_problems/{png,webp}

[[ -n "$SKIP" ]] || {

echo "[Convert RPGMVP images of problems into PNG]"

find '漢字でGO!/www/img/pictures' |
grep -E "Lv(Ca)?[0-9]+_[0-9]+.rpgmvp" |
grep -v '_0000.png' |
while read -r i
do
  [[ -n "$LOG" ]] && printf '\e[K\r%s' "$i"
  dest_name='./kanji_problems/png/'"$(basename "$i" | sed 's/rpgmvp/png/')"
  printf '\x89\x50\x4E\x47\x0D\x0A\x1A\x0A\x00\x00\x00\x0D\x49\x48\x44\x52' > "$dest_name"
  tail -c +33 "$i" >> "$dest_name"
done
[[ -n "$LOG" ]] && echo

echo "[Shrink PNG]"
find kanji_problems/png -name '*.png' | {
  if [[ -n "$LOG" ]]
  then
    xargs -P0 -I{} bash -c 'printf "\e[K\r{}" && mogrify -quality 1 -resize 200x {}'
  else
    xargs -P0 -I{} bash -c 'mogrify -quality 1 -resize 200x {}'
  fi
}
[[ -n "$LOG" ]] && echo

echo "[PNG -> WEBP]"
find kanji_problems/png -name '*.png' | sed -r 's_^.*/(Lv.*)\.png$_\1_' | {
  if [[ -n "$LOG" ]]
  then
    xargs -P0 -I{} bash -c 'printf "\e[K\r{}" && convert kanji_problems/png/{}.png kanji_problems/webp/{}.webp'
  else
    xargs -P0 -I{} bash -c 'convert kanji_problems/png/{}.png kanji_problems/webp/{}.webp'
  fi
}
[[ -n "$LOG" ]] && echo

}

echo "[HTML]"

levels=()
while read -r i
do
  levels+=("$i")
done < <(
  find kanji_problems/png -type f -name '*' |
  awk -F'[_/]' '$0=$(NF-1)' |
  sort -V | uniq
)

levels_len="${#levels[@]}"
for (( idx=0; idx<levels_len; idx++ ))
do
  level="${levels[idx]}"
  f="kanji_de_go_list_${level}.html"
  count="$(find kanji_problems/png -name "$level"'_*.png' | wc -l)"

  if [[ "$idx" != 0 ]]
  then
    prv="<span><a href='kanji_de_go_list_${levels[idx-1]}.html'>${levels[idx-1]}</a></span>"
  else
    prv=""
  fi
  if [[ "$((idx+1))" != "$levels_len" ]]
  then
    nxt="<span><a href='kanji_de_go_list_${levels[idx+1]}.html'>${levels[idx+1]}</a></span>"
  else
    nxt=""
  fi

  echo "${level} -> ${f}, ${count} problem(s)"
  { sed 's/^ *//' << EOS;} > "$f"
  <!DOCTYPE html>
  <html lang="ja" dir="ltr">
  <head>
  <meta charset="UTF-8">
  <title>${f//.*/}</title>
  <meta name="viewport" content="width=device-width,initial-scale=1">
  </head>
  <body>
  <h1>${level} -- 全${count}問</h1>
  ＜＜${prv:-}|<a href='index.html'>●</a>|${nxt:-}＞＞
  <table border=1>
  <thead>
  <tr>
  <th>ID</th>
  <th>問題</th>
  <th>答え</th>
  <th>解説</th>
  </tr>
  </thead>
  <tbody>
EOS

  grep "$level" kanji_de_go.tsv | while IFS=$'\t' read -r a b c d
  do
    cat<<EOS
    <tr>
    <td>${a}</td>
    <td><a href='kanji_problems/png/${a}.png'><img alt='${a}' width=200 height=57 loading='lazy' src='kanji_problems/webp/${a}.webp'></a></td>
    <td>${b}</td>
    <td>${c}${d}</td>
    </tr>
EOS
  done | sed 's/^ *//' >> "$f"

  sed 's/^ *//' <<'EOS'>> "$f"
  </tbody>
  </table>
  </body>
  </html>
EOS

done

if ! :
then
  echo "[OCR]"
  if ! command -v python &>/dev/null
  then
    echo "install: python" >&2
    exit 1
  fi
  if { python -m manga_ocr -h |& grep -q FLAGS;}
  then
    echo "run: pip install manga_ocr">&2
    exit 1
  fi

  python -c'
  from pathlib import Path
  import sys

  import manga_ocr

  m = manga_ocr.MangaOcr()
  for i in sorted(Path("kanji_problems").glob("*.png")):
    print(i, file=sys.stderr)
    print(m(i))
  ' > ocr_problem
fi

mkdir -p docs/
if [[ -d  docs/kanji_problems ]]
then
  rm -rf docs/kanji_problems
fi
mv kanji_problems kanji_de_go_list_Lv*.html docs

echo "[DONE!]"
