#!/usr/bin/env bash

set -x

git push github.com "$@"
git push righttoprivacy.onion "$@"
git push darktea.onion "$@"
