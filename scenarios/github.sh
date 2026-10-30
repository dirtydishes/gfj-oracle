#!/bin/sh
# Build the PR scenarios on github.com/dirtydishes/gfj-oracle with real gh.
# Idempotent: a scenario whose branch already exists on the remote is skipped.
#
#   scenarios/github.sh
#
# Scenarios (branch -> state):
#   s/pass      open PR, CI passes
#   s/fail      open PR, CI job `check` fails
#   s/pending   open PR, CI job `check` sleeps 45 minutes (pending while captures run)
#   s/draft     draft PR, CI passes
#   s/nochecks  open PR whose branch deletes the workflow, so no checks are reported
#   s/merged    PR merged with a merge commit
#   s/closed    PR closed without merging
set -eu

REPO=dirtydishes/gfj-oracle
REMOTE=${REMOTE:-github}
cd "$(dirname "$0")/.."

exists() { git ls-remote --exit-code --heads "$REMOTE" "$1" >/dev/null 2>&1; }

scenario() { # branch title setup-command [pr-create flags...]
  branch=$1 title=$2 setup=$3
  shift 3
  if exists "$branch"; then echo "skip $branch"; return; fi
  git switch -q -C "$branch" main
  sh -c "$setup"
  git add -A
  git commit -q -m "$title"
  git push -q -u "$REMOTE" "$branch"
  gh pr create -R "$REPO" --base main --head "$branch" --title "$title" \
    --body "Oracle scenario \`$branch\`. Do not merge by hand." "$@"
  git switch -q main
}

git fetch -q "$REMOTE" main
git switch -q main
git reset -q --hard "$REMOTE/main"

scenario s/pass     "scenario: checks pass"    'mkdir -p notes && echo pass > notes/pass.txt'
scenario s/fail     "scenario: checks fail"    'mkdir -p ci && echo "scenario s/fail" > ci/fail'
scenario s/pending  "scenario: checks pending" 'mkdir -p ci && echo 2700 > ci/slow'
scenario s/draft    "scenario: draft"          'mkdir -p notes && echo draft > notes/draft.txt' --draft
scenario s/nochecks "scenario: no checks"      'git rm -q .github/workflows/ci.yml'

if ! exists s/merged; then
  scenario s/merged "scenario: merged" 'mkdir -p notes && echo merged > notes/merged.txt'
  sleep 5
  gh pr merge s/merged -R "$REPO" --merge
fi
if ! exists s/closed; then
  scenario s/closed "scenario: closed" 'mkdir -p notes && echo closed > notes/closed.txt'
  gh pr close s/closed -R "$REPO"
fi

gh pr list -R "$REPO" --state all --json number,headRefName,state,isDraft
