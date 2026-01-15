#!/usr/bin/env bash

repo_name=alchi-journal

username=milahu

main_branches="main"

force=true

function git_remote_add() {

  local name="$1"
  local url="$2"

  exists=false
  if git remote get-url "$name" >/dev/null 2>&1; then
    exists=true
  fi

  if ! $force && $exists; then
    # remote with this name already exists
    echo "remote exists: $name"
    return
  fi

  # add username
  url="$(echo "$url" | sed -E "s|^(https?://)|\1${username}@|")"

  if ! $exists; then
    echo "adding remote: $name"
    git remote add "$name" "$url"
  else
    echo "updating remote: $name"
    git remote set-url "$name" "$url"
  fi

  if echo "$name" | grep -q '.onion$'; then
    echo "torifying remote: $name"
    git config --add "remote.$name.proxy" socks5h://127.0.0.1:9050
  fi

}



git_remote_add github.com https://github.com/$username/$repo_name

git_remote_add gitlab.com https://gitlab.com/$username/$repo_name

git_remote_add codeberg.org https://codeberg.org/$username/$repo_name

# git_remote_add sourceforge.net https://git.code.sourceforge.net/p/$username-$repo_name/code

git_remote_add notabug.org https://notabug.org/$username/$repo_name

git_remote_add disroot.org https://git.disroot.org/$username/$repo_name

git_remote_add sr.ht git@git.sr.ht:~$username/$repo_name

git_remote_add darktea.onion http://it7otdanqu7ktntxzm427cba6i53w6wlanlh23v5i3siqmos47pzhvyd.onion/$username/$repo_name

git_remote_add righttoprivacy.onion http://gg6zxtreajiijztyy5g6bt5o6l3qu32nrg7eulyemlhxwwl6enk6ghad.onion/$username/$repo_name

owner=$username
repo=$repo_name

git_remote_add darkforest.onion http://git.dkforestseeaaq2dqz2uflmlsybvnq2irzn4ygyvu53oazyorednviid.onion/$owner/$repo

git_remote_add gdatura.onion http://gdatura24gtdy23lxd7ht3xzx6mi7mdlkabpvuefhrjn4t5jduviw5ad.onion/$owner/$repo
