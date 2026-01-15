#!/usr/bin/env bash

# run this after scan-adf.sh
# TODO maybe integrate this into scan-adf.sh



find . -mindepth 1 -maxdepth 1 -type f -regextype posix-extended -regex '\./[0-9]{4}-[0-9]{2}-[0-9]{2}\.[0-9]{2}-[0-9]{2}.*\.avif' -printf '%P\n' |
while read image_path
do

  year_month=$(echo "$image_path" | sed -E 's/^([0-9]{4}-[0-9]{2})-.*$/\1/')

  if [[ "$year_month" == "$image_path" ]]; then
    echo "error: failed to parse year_month from image_path: $image_path"
    exit 1
  fi

  #echo "$year_month $image_path"

  mkdir -p "img/$year_month"

  output_path="img/$year_month/$(basename "$image_path")"

  if [[ -e "$output_path" ]]; then
    echo "error: output file exists: $output_path"
    exit 1
  fi

  mv "$image_path" "$output_path"

done
