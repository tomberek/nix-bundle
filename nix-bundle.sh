#!/usr/bin/env sh

if [ "$#" -lt 2 ]; then
    cat <<EOF

Usage: $0 TARGET EXECUTABLE

Create a single-file bundle from the nixpkgs attribute "TARGET".
EXECUTABLE should be relative to the TARGET's output path.

For example:

$ $0 hello /bin/hello
$ ./hello
Hello, world!

EOF

    exit 1
fi

nix_file=`dirname $0`/default.nix

target="$1"
shift

extraTargets=
if [ "$#" -gt 1 ]; then
    while [ "$#" -gt 1 ]; do
        extraTargets="$extraTargets $1"
        shift
    done
fi

exec="$1"
shift

bootstrap=nix-bootstrap
if [ "$target" = "nix-bundle" ] || [ "$target" = "nixStable" ] || [ "$target" = "nixUnstable" ] || [ "$target" = "nix" ]; then
    bootstrap=nix-bootstrap-nix
elif ! [ -z "$extraTargets" ]; then
    bootstrap=nix-bootstrap-path
fi

expr="with import <nixpkgs> {}; with import $nix_file {}; $bootstrap { target = $target; extraTargets = [ $extraTargets ]; run = \"$exec\"; }"

out=$(nix-store --no-gc-warning -r --option binary-caches '' $(nix-instantiate --no-gc-warning -E "$expr"))
#out=$(nix-store --no-gc-warning -r $(nix-instantiate --no-gc-warning -E "$expr"))

if [ -z "$out" ]; then
  >&2 echo "$0 failed. Exiting."
  exit 1
elif [ -t 1 ]; then
  filename=$(basename $exec)
  echo "Nix bundle created at $filename."
cat <<"EOF" > $filename
#!/bin/sh
if [ ! -z "$IN_NIX_USER_CHROOT"]; then
#! /nix/env nix-shell
#! nix-shell --pure -I nixpkgs=channel://nixpkgs-unstable -p hello -i sh
echo Modify this script for a self-installing nix-shell in a chroot.
echo "The store will persist in TMPDIR due to nix-bundle's arx approach."
echo "This hard-codes a channel, feel free to modify."
echo
echo "Perhaps try '-i python' for a run-anywhere-with-nix python script"
echo "Cons:"
echo "  Linux only due to nix-user-chroot"
echo "  nix-shell is slow to start"

echo "Arguments:"
shift
echo "$@"

### Don't remove this exit, or weird things happen ###
exit
#ENDSENTINEL
fi

ABSPATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
EOF
  cat $out | sed 's|exec ../run |exec ../run "$ABSPATH" |g' >> $filename
else
  cat $out
fi
