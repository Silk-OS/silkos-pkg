#!/bin/sh
# tests/verify/verify-test.sh
# Regression test for weave/util/verify.lua. Builds throwaway repos and keys in a
# temp directory and touches nothing else. KEEP=1 keeps the temp directory.
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
HERE="$ROOT/tests/verify"
export LUA_PATH="$ROOT/?.lua;$ROOT/?/init.lua;;"
export GIT_TERMINAL_PROMPT=0
T=$(mktemp -d /tmp/verify-test.XXXXXX)
[ -n "$KEEP" ] || trap 'rm -rf "$T"' EXIT
FAILS=0

G="git -c user.name=Test -c user.email=test@example.invalid"
SIGN="$G -c gpg.format=ssh"

mk_commit() { echo "$1" >> f; git add f; $G commit -q -m "$1"; }
signtag()   { $SIGN -c user.signingkey="$T/keys/$2" tag -s "$1" -m "$1"; }
run()       { LAST=$(lua "$HERE/verify-drive.lua" "$@" 2>&1); }
expect() {
  name=$1; shift; ok=1
  for re in "$@"; do
    printf '%s\n' "$LAST" | grep -Eq -- "$re" || ok=0
  done
  if [ "$ok" = 1 ]; then
    echo "PASS  $name"
  else
    echo "FAIL  $name"
    printf '%s\n' "$LAST" | sed 's/^/        /'
    FAILS=$((FAILS + 1))
  fi
}

mkdir -p "$T/keys"
ssh-keygen -q -t ed25519 -N '' -C trusted -f "$T/keys/trusted"
ssh-keygen -q -t ed25519 -N '' -C rogue   -f "$T/keys/rogue"
printf 'release@silk.test namespaces="git" %s\n' "$(cat "$T/keys/trusted.pub")" > "$T/signers"

# ---- origin 1: trusted history
git init -q --bare "$T/origin.git"
git init -q "$T/work"; cd "$T/work"
mk_commit c1; git branch -M main; signtag v1 trusted
git push -q "$T/origin.git" main --tags

run "$T/client" "$T/origin.git" "$T/signers"
expect "1. fresh client, valid trusted tag" 'RESULT: ok tag=v1 .* changed=true skipped=0\[\]'
run "$T/client" "$T/origin.git" "$T/signers"
expect "2. resync, nothing new" 'RESULT: ok tag=v1 .* changed=false skipped=0\[\]'

sleep 2; cd "$T/work"; mk_commit c2; signtag v2 trusted
git push -q "$T/origin.git" main --tags
run "$T/client" "$T/origin.git" "$T/signers"
expect "3. newer valid tag on a descendant" 'RESULT: ok tag=v2 .* changed=true skipped=0\[\]'

sleep 2; cd "$T/work"; mk_commit c3; signtag v3 rogue
sleep 2; $G tag -a v4 -m v4
git push -q "$T/origin.git" main --tags
run "$T/client" "$T/origin.git" "$T/signers"
expect "4. rogue-signed v3 and unsigned v4 are skipped" \
  "skipping tag 'v4'" "skipping tag 'v3'" 'RESULT: ok tag=v2 .* changed=false skipped=2\[v4,v3\]'

sleep 2; cd "$T/work"; git checkout -q --orphan rewrite; mk_commit x1; signtag v5 trusted
git push -q "$T/origin.git" refs/tags/v5
run "$T/client" "$T/origin.git" "$T/signers"
expect "5. trusted tag on unrelated history is refused" \
  "REFUSING tag 'v5'" 'RESULT: ok tag=v2 .* changed=false skipped=3\[v5,v4,v3\]'

# ---- origin 2: only bad tags
git init -q --bare "$T/origin2.git"; git init -q "$T/work2"; cd "$T/work2"
mk_commit w1; signtag r1 rogue; sleep 2; $G tag -a u1 -m u1
git push -q "$T/origin2.git" --tags
run "$T/client2" "$T/origin2.git" "$T/signers"
expect "6. only rogue/unsigned tags" 'RESULT: error: .*no usable tag'

run "$T/client3" "$T/origin.git" "$T/nope"
expect "7. signers file missing" 'RESULT: unavailable: trusted signers file missing'

# ---- origin 3: a branch but no tags
git init -q --bare "$T/origin3.git"; git init -q "$T/work3"; cd "$T/work3"
mk_commit n1; git branch -M main; git push -q "$T/origin3.git" main
run "$T/client4" "$T/origin3.git" "$T/signers"
expect "8. repo with no tags" 'RESULT: unavailable: no tags published yet'

# ---- origin 5: upstream moves a tag the client already has
git init -q --bare "$T/origin5.git"; git init -q "$T/work5"; cd "$T/work5"
mk_commit m1; git branch -M main; signtag v1 trusted
git push -q "$T/origin5.git" main --tags
run "$T/client5" "$T/origin5.git" "$T/signers"
expect "9a. baseline sync before the tag moves" 'RESULT: ok tag=v1 .* changed=true'
sleep 2; mk_commit m2
$SIGN -c user.signingkey="$T/keys/trusted" tag -f -s v1 -m v1-moved
git push -q --force "$T/origin5.git" main refs/tags/v1
run "$T/client5" "$T/origin5.git" "$T/signers"
expect "9b. a moved tag makes the sync unavailable (fetch refuses to clobber it)" 'RESULT: unavailable'

# ---- origin 6: key validity window in the signers file
printf 'release@silk.test namespaces="git",valid-before="20991231" %s\n' "$(cat "$T/keys/trusted.pub")" > "$T/signers-future"
printf 'release@silk.test namespaces="git",valid-before="20200101" %s\n' "$(cat "$T/keys/trusted.pub")" > "$T/signers-expired"
git init -q --bare "$T/origin6.git"; git init -q "$T/work6"; cd "$T/work6"
mk_commit k1; git branch -M main; signtag v1 trusted
git push -q "$T/origin6.git" main --tags
run "$T/client6" "$T/origin6.git" "$T/signers-future"
expect "10a. key valid until 2099 still works (control)" 'RESULT: ok tag=v1 .* changed=true'
run "$T/client7" "$T/origin6.git" "$T/signers-expired"
expect "10b. key retired in 2020: a tag made now is not trusted" \
  "skipping tag 'v1'" 'RESULT: error: .*no usable tag'

echo
if [ "$FAILS" -eq 0 ]; then
  echo "all verify tests passed"
else
  echo "$FAILS verify test(s) FAILED"
  exit 1
fi
