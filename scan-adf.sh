#! /usr/bin/env bash

# scan-adf.sh
# single pass duplex scanning of multiple pages (ADF)
# with Brother ADS-3000N scanner

# TODO prevent focus-stealing from the "feh" image viewer
# on KDE plasma:
# feh window title bar -> rightclick -> more actions ->
# configure special application settings ->
# add property -> focus stealing prevention -> add ->
# change from "none" to "high"

# set -x # debug


this_user_uid=$(id --user)
this_user_gid=$(id --group)

output_user_uid=1000
output_user_gid=100

tempdir="/run/user/$output_user_uid"

keep_tempfile=true # debug
keep_tempfile=false

write_logfile=true # debug
write_logfile=false



do_chown=false

if ((output_user_uid != this_user_uid)) || ((output_user_gid != this_user_gid)); then
  do_chown=true
fi

# TODO dynamic. use "lsusb" to find the scanner device
# sudo scanimage -L
# $ sudo scanimage -L 
# device `brother5:bus1;dev3' is a Brother ADS-3000N USB scanner
# note: "dev3" does not correspond with output of lsusb
# $ lsusb | grep ADS-3000N
# Bus 001 Device 073: ID 04f9:03b8 Brother Industries, Ltd ADS-3000N
# $ sudo scanimage -L 
# device `brother4:bus4;dev1' is a Brother ADS-3000N USB scanner
# device `brother5:bus1;dev4' is a Brother ADS-3000N USB scanner
device_name="brother5:bus1;dev3"
device_name="brother5:bus1;dev4"
device_name="brother5:bus2;dev2" # Bus 002 Device 020: ID 04f9:03b8 Brother Industries, Ltd ADS-3000N
device_name="$1"
shift
if [ -z "$device_name" ]; then
  echo "error: missing argument: device_name" >&2
  echo "example use: $0 brother5:bus2;dev2" >&2
  echo "hint: use this to get the device name: scanimage -L" >&2
  exit 1
fi

# sudo scanimage --device-name="$device_name" --help
#source="Flatbed"
source="Automatic Document Feeder(left aligned,Duplex)"

# 24bit Color[Fast]
# Black & White
# True Gray
# Gray[Error Diffusion]
mode="24bit Color[Fast]"



# see benchmark.txt
# pnm and tiff are fastest and best quality
# png is much slower
format=pnm



# din a4: 210 x 297 mm
extra_options=(--MultifeedDetection=yes --SkipBlankPage=no -x 210 -y 297)



quality=40%

small_scale=50%

# 15 MByte png file
resolution=300


if [[ "$(id -u)" != "0" ]]; then
  echo "error: you must run this script as root. hint: sudo $0"
  exit 1
fi



if false; then
# scan about 10 white sheets to test the scan quality
# if there are vertical grey lines then clean the sensor glass with water or acetone
# see also: done-vertical-lines-from-adf-scanner.txt
sudo scanimage --device-name=brother5:bus1\;dev3 --resolution=300 --format=pnm \
  --batch=/run/user/1000/scan-calibration.%d.pnm --batch-print --mode=24bit\ Color\[Fast\] \
  --source=Automatic\ Document\ Feeder\(left\ aligned\,Duplex\) --MultifeedDetection=yes \
  --SkipBlankPage=no -x 210 -y 297
d1=scan-calibration.$(date -Is --utc);
for pnm in /run/user/1000/scan-calibration.*.pnm; do
  n=${pnm%.*}; n=${n##*.}; np=$(printf "%03d\n" $n);
  d2=even; if ((n % 2 == 1)); then d2=odd; fi;
  png=$d1/$d2/$np.png;
  mkdir -p $(dirname $png);
  echo writing $png;
  magick $pnm $png;
done
fi



# contrast: increase contrast to remove noise in document scans
# https://superuser.com/questions/622950/is-there-a-way-to-increase-the-contrast-of-a-pdf-that-was-created-by-scanning-a
# http://www.fmwconcepts.com/imagemagick/thresholds/index.php # -t soft -l 25 -h 75
# to find these threshold values, use gimp > colors > levels
#lowthresh=15 # text is too light
lowthresh=40 # produce dark text # 40/100 = 100/256
# highthresh:
# lower = more white, less artefacts, more loss of grey lines
#highthresh=80
# 98 is better than 100
# to convert a slightly grey background to a pure white background
highthresh=98
# i need to go this low, to remove vertical grey lines produced by my ADF scanner
# see also https://github.com/ImageMagick/ImageMagick/discussions/6042
#highthresh=85
# i really need to go THIS low to remove all grey lines on all pages. oof!
# this is lossy, because my hand-written text also contains grey lines
#highthresh=66 # 66/100 = 170/256

# set profile to fix red tint (red color cast)
# https://blog.teamgeist-medien.de/2015/07/typo3-graphicsmagick-rotstich-bei-bildern-beheben-farbfehler.html
# https://legacy.imagemagick.org/discourse-server/viewtopic.php?t=22549
#large_convert_options+=( -set colorspace RGB +profile '*' )

# my document scanner adds a white bar below the scanned image. remove it by cropping
# input size: 2480x3508
crop_x=2480; crop_y=3342 # resolution=300

shared_convert_options=(
  "${extra_convert_options[@]}"
  -set colorspace RGB
  +profile '*'
  -quality $quality
  # "+repage" required for webp output with "-crop"
  # "+0+0" is required for "-crop" otherwise it produces multiple images
  #   or an animated webp image with multiple frames
  -crop $crop_x"x"$crop_y+0+0 +repage
  # "-coalesce" is required for webp output
  # https://github.com/ImageMagick/ImageMagick/issues/6041
  -coalesce
);

small_convert_options=(
  #"${shared_convert_options[@]}"
  -scale $small_scale
  -level ${lowthresh}x${highthresh}%
);

large_convert_options=(
  #"${shared_convert_options[@]}"
);



# batch convert
# code to manually scan one page from flatbed
if false; then
date_time=$(date +%Y-%m-%d.%H-%M-%S)
mkdir /run/user/$(id --user) 2>/dev/null || true
temp_path="$tempdir/scan.$date_time.1.$format"
set -x
scanimage \
  --device-name="$device_name" \
  --resolution=$resolution \
  --format=$format \
  --output-file="$temp_path" \
  --mode=Color \
  --source="$source" \
  "${extra_options[@]}"
set +x
echo "done $temp_path"
fi



# batch convert
# code to manually convert some temporary png files
if false; then
for temp_path in $tempdir/scan.$(date +"%Y-%m-%d.")*.$format;
do
  bth=40;
  wth=98;
  scale=50%;
  quality=80;
  small_scale=50%;
  extra_convert_options=()
  #extra_convert_options=(-rotate 90)
  # thresholds can produce ugly transparent output. example: scan.2023-10-03.10-31-42.1.webp
  #   -black-threshold $bth% -white-threshold $wth%
  # level should be enough:
  #   -level $bth"x"$wth%
  shared_convert_options=("${extra_convert_options[@]}"
    -set colorspace RGB +profile '*' -quality $quality
  );
  small_convert_options=("${shared_convert_options[@]}"
    -scale $small_scale -level $bth"x"$wth%);
  large_convert_options=("${shared_convert_options[@]}");
  out_small="$(basename "$temp_path" .$format).avif";
  out_large="large/$(basename "$temp_path" .$format).large.avif";
  # note: convert already uses multiple cpu cores
  # so dont run convert in parallel, or set MAGICK_THREAD_LIMIT=1
  # https://superuser.com/questions/316365/parallel-processing-slower-than-sequential
  set -x;
  echo "writing $out_large"
  magick "$temp_path" "${large_convert_options[@]}" "$out_large";
  echo "writing $out_small"
  magick "$temp_path" "${small_convert_options[@]}" "$out_small";
  set +x;
done
fi



# date
date_time=$(date +%Y-%m-%d.%H-%M-%S)

mkdir /run/user/$(id --user) 2>/dev/null || true

# tempfile path format
# "%d" will be replaced by an incrementing number
temp_path_format="$tempdir/scan.$date_time.%d.$format"

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



  # this is fancy but slow
  # TODO find something better to rename and rotate images
  #if false; then



  # show image
  # dont connect feh to stdin or stdout
  # otherwise input-line-editing is broken (backspace creates ugly input)
  feh --scale-down "$temp_path" </dev/zero >/dev/null 2>&1 &
  feh_pid=$!

  this_extra_convert_options=()

  # ask user
  echo "  e = edit the image with gimp"
  #echo "  k = delete the image and rescan it later"
  echo "  k = delete the image"
  echo "  r = rotate by 90 degrees to the right = clockwise"
  echo "  v = rotate by 180 degrees"
  echo "  l = rotate by 90 degrees to the left = counter clockwise"
  echo "  * = continue (press any other key, like enter or space)"
  echo -n "what should i do? "
  #read_char response
  read -n1 response
  echo

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
      if false; then
        echo "adding page $temp_path_number to the 'TODO rescan pages' list"
        todo_rescan_pages+=" $temp_path_number"
      fi
      kill $feh_pid 2>/dev/null
      continue
      ;;
    r)
      this_extra_convert_options+=(-rotate 90)
      ;;
    v)
      this_extra_convert_options+=(-rotate 180)
      ;;
    l)
      this_extra_convert_options+=(-rotate 270)
      ;;
    *)
      echo "continuing to process $temp_path"
  esac



  default_title="$(basename "$temp_path")"
  # remove extension
  default_title="${default_title%.*}"
  # remove the "scan." prefix
  # move-images.sh expects filenames like 2023-11-25.06-00.some-name
  default_title="${default_title#scan.}"

  if [ -n "$last_title" ]; then
    # re-use the datetime of the last title
    # datetime format: yyyy-mm-dd.hh-mm
    default_title=$(echo "$last_title" | sed -E 's/^([0-9]{4}-[0-9]{2}-[0-9]{2}\.[0-9]{2}-[0-9]{2})\..*$/\1/')
  fi

  # retry loop
  while true; do

    # ask user for filename
    read -e -p "please enter the basename: " -i "$default_title" title

    # trim the entered title
    title="$(echo "$title" | sed -E 's/^[ \t\r]+//; s/[ \t\r]+$//')"

    # remove "\r"
    # replace whitespace with "."
    title="$(echo "$title" | sed -E 's/[\r]+//g; s/[ \t]+/./g')"

    if [ -z "$title" ]; then
      title="$default_title"
    fi

    # hard limit: 255 bytes
    # 255 - len(".large") = 249
    title_len_max=240

    ask_again=false
    for o in "$title.avif" "large/$title.large.avif"; do
      if [ -e "$o" ]; then
        echo "error: output file exists: $o"
        ask_again=true
      fi
    done
    $ask_again && continue # ask again

    [ ${#title} -lt $title_len_max ] && break

    echo "error: title is too long. ${#title} versus $title_len_max. please use a shorter title"
    default_title="$title"

  done

  echo "using basename: ${title@Q}"



  kill $feh_pid 2>/dev/null



  # run "convert" processes in background
  # so they run in parallel and the loop can continue
  # we only have to keep the "$temp_path" files
  # until all "convert" are done
  # but we keep "$temp_path" anyway, so... works for now



  # convert large

  o="large/$title.large.avif"

  [ -d large ] || mkdir -p large

  echo creating "$o"

  convert_args_large=(
    magick
    "$temp_path"
    "${extra_convert_options[@]}"
    "${shared_convert_options[@]}"
    "${this_extra_convert_options[@]}"
    "${large_convert_options[@]}"
    "$o"
  )
  echo "${convert_args_large[@]}"

  # convert small

  o_small="$title.avif"

  echo creating "$o_small"

  convert_args_small=(
    magick
    "$temp_path"
    "${extra_convert_options[@]}"
    "${shared_convert_options[@]}"
    "${this_extra_convert_options[@]}"
    "${small_convert_options[@]}"
    "$o_small"
  )
  echo "${convert_args_small[@]}"

  if $keep_tempfile; then
    echo keeping tempfile "$temp_path"
  fi

  # run "convert" in the background
  # and continue with the next image
  (
    "${convert_args_large[@]}"
    if $do_chown; then
      chown $output_user_uid:$output_user_gid "$o"
    fi
    "${convert_args_small[@]}"
    if $do_chown; then
      chown $output_user_uid:$output_user_gid "$o_small"
    fi
    if $keep_tempfile; then
      if $do_chown; then
        chown $output_user_uid:$output_user_gid "$temp_path"
      fi
    else
      rm -f "$temp_path"
    fi
  ) &

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

  last_title="$title"

done 3< <(

  # redirect stderr to log file to keep the terminal clean
  # TODO better. buffer the output and print it as soon as possible, dont create a logfile
  if $write_logfile; then
    scanimage_log_path="$tempdir/scanimage.$(date -Is --utc).log"
    echo "writing scanimage log to $scanimage_log_path" >&2
  fi

  #set -x

  # FIXME --batch-print is not working?

  scanimage_args=(
    scanimage
    --device-name="$device_name"
    --resolution=$resolution
    --format=$format
    --batch="$temp_path_format"
    --batch-print
    --mode="$mode"
    --source="$source"
    "${extra_options[@]}"
  )

  printf "%q " "${scanimage_args[@]}" >&2; echo >&2

  if $write_logfile; then
    echo "writing logfile $scanimage_log_path" >&2
    "${scanimage_args[@]}" 2>"$scanimage_log_path"
  else
    "${scanimage_args[@]}" \
      2> >(grep -v -E "^(Scanning page|Scanned page|scanimage: sane_read: Document feeder out of documents|Batch terminated)" >&2)
  fi

)



if false; then
if [ -n "$todo_rescan_pages" ]; then
  echo "TODO rescan pages:" $todo_rescan_pages
fi
fi



exit



# open result

echo opening "$o_small" ...
"${image_viewer[@]}" "$o_small" &

