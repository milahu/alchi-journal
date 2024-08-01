#!/usr/bin/env bash

set -eux

shopt -s nullglob

./move-images.sh

./generate-index-files.sh

git add img/*/*.webp
git add html/????-??.html
git add index.html || true
git add ????-??.md

git commit -m "add images"

git status
