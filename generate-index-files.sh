#!/usr/bin/env bash

cd "$(dirname "$0")"

find img/ -mindepth 1 -maxdepth 1 -type d -regextype posix-extended -regex 'img/[0-9]{4}-[0-9]{2}' -printf '%P\n' |
sort |
while read month
do

  echo writing $month.md

  (
    printf '# %s\n\n' "$month"

    find img/$month/ -maxdepth 1 -name "$month-*.webp" |
    sort |
    while read f
    do
      n=${f##*/}
      printf '## %s\n\n' "$n"
      printf '![](%s)\n\n' "$f"
    done
  ) >$month.md

  echo writing $month.html

  (
    printf '<h1>%s</h1>\n\n' "$month"

    find img/$month/ -maxdepth 1 -name "$month-*.webp" |
    sort |
    while read f
    do
      n=${f##*/}
      printf '<h2>%s</h2>\n\n' "$n"
      printf '<img src="%s">\n\n' "$f"
    done
  ) >$month.html

done

echo writing index.html

(
  find img/ -mindepth 1 -maxdepth 1 -type d -regextype posix-extended -regex 'img/[0-9]{4}-[0-9]{2}' -printf '%P\n' |
  sort |
  while read month
  do

    printf '<p><a href="%s.html">%s</a></p>\n\n' "$month" "$month"

  done
) >index.html
