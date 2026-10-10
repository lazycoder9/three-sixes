#!/usr/bin/env bash
# A fresh worktree has none of the main checkout's gitignored build state, and building it from
# scratch takes minutes, so it is cloned from there and then brought up to this branch's lockfiles.

set -euo pipefail

root=$(git rev-parse --show-toplevel)
main=${THREE_SIXES_MAIN_CHECKOUT:-$(git worktree list --porcelain | sed -n '1s/^worktree //p')}
cd "$root"

if [ "$root" = "$main" ]; then
  echo "worktree_setup: $root is the main checkout; nothing to do."
  exit 0
fi

step() { printf '\n== %s\n' "$*"; }

failed=""
warn() {
  failed="$failed $1;"
  echo "worktree_setup: warning: $1 failed; rerun bash scripts/worktree_setup.sh" >&2
}

# GNU cp shadows /bin/cp in PATH and rejects -c, so the macOS binary is named in full.
clone() {
  local path=$1
  if [ -e "$path" ]; then
    echo "  $path: present"
  elif [ -e "$main/$path" ]; then
    mkdir -p "$(dirname "$path")"
    /bin/cp -Rc "$main/$path" "$path" 2>/dev/null || cp -R "$main/$path" "$path"
    echo "  $path: cloned from $main"
  else
    echo "  $path: not in the main checkout either; installing from scratch below"
  fi
}

link() {
  local path=$1
  if [ -e "$path" ] || [ -L "$path" ]; then
    echo "  $path: present"
  elif [ -e "$main/$path" ]; then
    mkdir -p "$(dirname "$path")"
    ln -s "$main/$path" "$path"
    echo "  $path -> $main/$path"
  fi
}

step "Cloning build state from $main"
for path in deps _build assets/node_modules priv/plts; do
  clone "$path"
done

step "Linking shared local files"
link notes
# Kamal reads its secrets from the checkout it runs in, so a deploy can run from a worktree.
link .kamal/secrets

# The clones match the main checkout's commit, which can lag this branch's lockfiles.
step "mix deps.get"
mix deps.get || warn "mix deps.get"

step "bun install in assets/"
(cd assets && bun install --frozen-lockfile) || warn "bun install in assets/"

# The dev database is a SQLite file inside the checkout, so each worktree gets its own.
step "Dev database"
(mix ecto.create --quiet && mix ecto.migrate --quiet) || warn "the dev database"

if [ -n "$failed" ]; then
  step "Done with warnings:$failed rerun bash scripts/worktree_setup.sh"
else
  step "Done: $root is ready"
fi
