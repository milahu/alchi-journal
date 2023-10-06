#! /usr/bin/env bash



quality=80

small_scale=50%

# 15 MByte png file
resolution=300




# https://imagemagick.org/script/webp.php
# these produce large output:
# -define webp:alpha-compression=0
# -define webp:exact=true
# thresholds can produce ugly transparent output. example: scan.2023-10-03.10-31-42.1.webp
#   -black-threshold $bth% -white-threshold $wth%
#   -black-threshold "${lowthresh}%" -white-threshold "${highthresh}%"
# level should be enough:
#   -level ${lowthresh}x${highthresh}%

# contrast: increase contrast to remove noise in document scans
# https://superuser.com/questions/622950/is-there-a-way-to-increase-the-contrast-of-a-pdf-that-was-created-by-scanning-a
# http://www.fmwconcepts.com/imagemagick/thresholds/index.php # -t soft -l 25 -h 75
# to find these threshold values, use gimp > colors > levels
lowthresh=40
# highthresh:
# lower = more white, less artefacts, more loss of grey lines
#highthresh=80
# 98 is better than 100
# to convert a slightly grey background to a pure white background
highthresh=98

# set profile to fix red tint (red color cast)
# https://blog.teamgeist-medien.de/2015/07/typo3-graphicsmagick-rotstich-bei-bildern-beheben-farbfehler.html
# https://legacy.imagemagick.org/discourse-server/viewtopic.php?t=22549
#large_convert_options+=( -set colorspace RGB +profile '*' )

shared_convert_options=("${extra_convert_options[@]}"
  -set colorspace RGB
  +profile '*'
  -quality $quality
  -define webp:lossless=false
  -define webp:auto-filter=true
  -define webp:image-hint=graph
);

small_convert_options=("${shared_convert_options[@]}"
  -scale $small_scale
  -level ${lowthresh}x${highthresh}%
);

large_convert_options=("${shared_convert_options[@]}");



# batch convert
# code to manually scan one page from flatbed
if false; then
date_time=$(date +%Y-%m-%d.%H-%M-%S)
mkdir /run/user/$(id --user) 2>/dev/null || true
temp_path="/run/user/$(id --user)/scan.$date_time.1.png"
set -x
scanimage \
  --device-name=escl:http://192.168.178.161:80 \
  --resolution=300 \
  --format=png \
  --output-file="$temp_path" \
  --mode=Color \
  --source=Flatbed
set +x
echo "done $temp_path"
fi



# batch convert
# code to manually convert some temporary png files
if false; then
for png in /run/user/$(id --user)/scan.$(date +"%Y-%m-%d.")*.png;
do
  bth=40;
  wth=98;
  scale=50%;
  quality=80;
  small_scale=50%;
  extra_convert_options=()
  #extra_convert_options=(-rotate 90)
  # https://imagemagick.org/script/webp.php
  # these produce large output:
  # -define webp:alpha-compression=0
  # -define webp:exact=true
  # thresholds can produce ugly transparent output. example: scan.2023-10-03.10-31-42.1.webp
  #   -black-threshold $bth% -white-threshold $wth%
  # level should be enough:
  #   -level $bth"x"$wth%
  shared_convert_options=("${extra_convert_options[@]}"
    -set colorspace RGB +profile '*' -quality $quality
    -define webp:lossless=false
    -define webp:auto-filter=true -define webp:image-hint=graph);
  small_convert_options=("${shared_convert_options[@]}"
    -scale $small_scale -level $bth"x"$wth%);
  large_convert_options=("${shared_convert_options[@]}");
  webp_small="$(basename "$png" .png).webp";
  webp_large="large/$(basename "$png" .png).large.webp";
  set -x;
  convert "$png" "${large_convert_options[@]}" "$webp_large";
  convert "$png" "${small_convert_options[@]}" "$webp_small";
  set +x;
done
fi



# date
date_time=$(date +%Y-%m-%d.%H-%M-%S)

mkdir /run/user/$(id --user) 2>/dev/null || true

# tempfile path format
# "%d" will be replaced by an incrementing number
temp_path_format="/run/user/$(id --user)/scan.$date_time.%d.png"

# add zero-padding to the page number
# to fix the sort order of files
# without having to use "ls --sort=version" etc
# this format string is passed to printf like
# $ printf "%03d" 1
# 001
page_number_format="%03d"



# pass all args of this script to convert (TODO better?)
# example: -rotate 90
extra_convert_options=("$@")



# https://stackoverflow.com/a/30022297/10440128
# read_char var
# FIXME stty: 'standard input': Inappropriate ioctl for device
read_char() {
  set -x
  stty -icanon -echo
  #eval "$1=\$(dd bs=1 count=1 2>/dev/null)"
  # fix for input '\n'
  eval "$1=\$'\\x$(dd bs=1 count=1 2>/dev/null | xxd -p)'"
  # this breaks line-editing with "read"
  #stty icanon echo
  stty sane
  set +x
}



todo_rescan_pages=""



# https://stackoverflow.com/questions/6883363/read-user-input-inside-a-loop
# https://stackoverflow.com/questions/16854280/a-variable-modified-inside-a-while-loop-is-not-remembered
# while read n <&3; do echo n=$n; read i; echo i=$i; done 3< <(seq 3)

while read temp_path <&3; do

  echo "temp path: $temp_path"

  # add zero-padding to the page number
  # get extension
  temp_path_extension="${temp_path##*.}"
  # remove extension
  temp_path_base="${temp_path%.*}"
  # get page number
  temp_path_number="${temp_path_base##*.}"
  # remove page number
  temp_path_base="${temp_path_base%.*}"
  temp_path_new="$temp_path_base.$(printf "$page_number_format" "$temp_path_number").$temp_path_extension"
  mv -v "$temp_path" "$temp_path_new"
  temp_path="$temp_path_new"


  # show image
  # dont connect feh to stdin or stdout
  # otherwise input-line-editing is broken (backspace creates ugly input)
  feh --scale-down "$temp_path" </dev/zero >/dev/null 2>&1 &
  feh_pid=$!

  # ask user
  echo "  e = edit the image with gimp"
  echo "  k = delete the image and rescan it later"
  echo "  * = continue (press any other key, like enter or space)"
  echo -n "what should i do? "
  #read_char response
  read -n1 response

  case "$response" in
    e)
      # edit
      gimp "$temp_path" &
      echo "edit the image in gimp, then: file > overwrite"
      echo "hit enter when done editing"
      read
      ;;
    #r) # no, "r" is too close to "e"
    k)
      # rescan
      rm -v "$temp_path"
      echo "adding page $temp_path_number to the 'TODO rescan pages' list"
      todo_rescan_pages+=" $temp_path_number"
      continue
      ;;
    *)
      echo "continuing to process $temp_path"
  esac



  default_title="$(basename "$temp_path")"
  # remove extension
  default_title="${default_title%.*}"



  # ask user for filename
  echo "default basename: $default_title"
  echo "hit enter to use the default basename"
  echo -n "what is the basename? "
  read title
  # trim the entered title
  title="$(echo "$title" | sed -E 's/^[ \t\r]+//; s/[ \t\r]+$//')"

  if [ -z "$title" ]; then
    title="$default_title"
  fi

  echo "using basename: ${title@Q}"



  kill $feh_pid



  # run "convert" processes in background
  # so they run in parallel and the loop can continue
  # we only have to keep the "$temp_path" files
  # until all "convert" are done
  # but we keep "$temp_path" anyway, so... works for now



  # convert large

  o="large/$title.large.webp"

  echo creating "$o"

  set -x
  convert "$temp_path" "${extra_convert_options[@]}" "${large_convert_options[@]}" "$o" &
  set +x



  # convert small

  o_small="$title.webp"

  echo creating "$o_small"

  set -x
  convert "$temp_path" "${extra_convert_options[@]}" "${small_convert_options[@]}" "$o_small" &
  set +x



  # remove tempfile
  #rm -f "$temp_path"

  # keep tempfile
  echo keeping tempfile "$temp_path"

  # the original tempfile is useful
  # to produce high-quality transformed images
  # transformed? usually rotation by 90 / 180 / 270 degrees

  # lossless rotation is only possible with jpeg images
  # not with compressed image formats like webp, jp2, ...
  # (png is an uncompressed image format)
  # but once correctly rotated, webp gives best quality for file size

  # jp2 is useful for embedding in pdf documents
  # because jp2 images are smaller than jpg images
  # and because pdf does not support webp images
  # TODO in the future, delete the tempfile when its no longer needed
  # find "$(dirname "$temp_path")" -mtime +10min -delete # ... or so

done 3< <(

  # redirect stderr to log file to keep the terminal clean
  scanimage_log_path=$(mktemp --suffix=.scanimage.log)
  echo "writing scanimage log to $scanimage_log_path" >&2

  scanimage \
    --device-name=escl:http://192.168.178.161:80 \
    --resolution=300 \
    --format=png \
    --batch="$temp_path_format" \
    --batch-print \
    --mode=Color \
    --source=ADF 2>"$scanimage_log_path"

)



if [ -n "$todo_rescan_pages" ]; then
  echo "TODO rescan pages:" $todo_rescan_pages
fi



exit



# open result

echo opening "$o_small" ...
"${image_viewer[@]}" "$o_small" &

