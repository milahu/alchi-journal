#! /usr/bin/env bash

set -e

user_name=milahu

repo_name=alchi-journal

# chdir to repo root
cd "$(dirname "$0")"/..

repo_root="$(pwd)"

tempdir=$(mktemp -d)
echo "using tempdir $tempdir"
cd $tempdir

echo "cloning from '$repo_root' to '$tempdir/$repo_name'"
git clone --depth=1 "file://$repo_root" $repo_name
cd $repo_name

ls -A
git log | head
git status



echo pushing files to sourceforge.net

# https://sourceforge.net/p/forge/documentation/rsync/#project-web-use

# rsync --delete: delete extraneous files from dest dirs
# rsync --cvs-exclude: ignore .git/
# rsync --links: copy symlinks as symlinks

# https://sourceforge.net/p/forge/documentation/SSH%20Key%20Fingerprints/
# web.sourceforge.net, web.sf.net, frs.sourceforge.net, frs.sf.net
# SHA256:209BDmH3jsRyO9UeGPPgLWPSegKmYCBIya0nR/AWWCY

known_hosts_line='web.sourceforge.net ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOQD35Ujalhh+JJkPvMckDlhu4dS7WH6NsOJ15iGCJLC'
if ! grep -q -x "$known_hosts_line" $HOME/.ssh/known_hosts; then
  echo "$known_hosts_line" >>$HOME/.ssh/known_hosts
fi

# https://stackoverflow.com/questions/3299951/how-to-pass-password-automatically-for-rsync-ssh-command
password_file="$repo_root/secrets/password-web.sourceforge.net.txt"

# no. The --password-file option may only be used when accessing an rsync daemon.
# rsync --password-file="$password_file"

if ! [ -e "$password_file" ]; then
  echo "error: missing password file: $password_file"
  exit 1
fi

# rsync --rsh=ssh: interactive login

ssh_username=$user_name
ssh_password=$(cat "$password_file")

rsync --recursive --compress --delete --cvs-exclude --links \
  --rsh="sshpass -p $ssh_password ssh -o StrictHostKeyChecking=no -l $ssh_username" \
  ./ $user_name@web.sourceforge.net:/home/project-web/$user_name-$repo_name/htdocs/

echo removing tempdir $tempdir
rm -rf $tempdir
