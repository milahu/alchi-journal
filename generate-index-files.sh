#!/usr/bin/env bash

find img/ -mindepth 1 -maxdepth 1 -type d -regextype posix-extended -regex 'img/[0-9]{4}-[0-9]{2}' -printf '%P\n' |
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

done
