#!/bin/bash
# Your brain - one-command setup for macOS. Neutral: works for any brain zip, no client names inside.
# Run in Terminal:
#   curl -fsSL https://royazaria.github.io/hamoach-sheli/install.sh | bash
# Installs Obsidian and the Claude desktop app (includes Claude Code), creates the folder "המוח שלי" in the home
# folder, adds the agent kit (CLAUDE.md + skills), unpacks the newest *המוח*.zip from Downloads into it, registers
# the folder as an Obsidian vault, and opens everything.
# Re-running with a newer zip updates the brain: files she added stay, and any file the zip replaces with different
# content is first copied to _גיבוי/<date time>/. Nothing is ever deleted. No rsync needed (newer macOS ships openrsync).
# Test without installing anything:  BRAIN_DRYRUN=1 BRAIN_ROOT=/tmp/x BRAIN_DOWNLOADS=/tmp/dl bash install.sh

set -u
BASE="${BRAIN_BASE:-https://royazaria.github.io/hamoach-sheli}"
DRY="${BRAIN_DRYRUN:-0}"
UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0 Safari/537.36"
VAULT_NAME="המוח שלי"
RAW_NAME="_גולמי"
MAT_NAME="חומרים"
BAK_NAME="_גיבוי"
BRAIN_WORD="המוח"
ROOT="${BRAIN_ROOT:-$HOME}"
VAULT="$ROOT/$VAULT_NAME"
TMP="$(mktemp -d -t brain.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

say()  { printf '\n\033[33m>> %s\033[0m\n' "$1"; }
ok()   { printf '   \033[32mOK\033[0m  %s\n' "$1"; }
warn() { printf '   \033[35m!!\033[0m  %s\n' "$1"; }
fail() { printf '\n\033[31mSomething went wrong: %s\033[0m\n\033[31mTake a screenshot of this window and send it to whoever sent you the brain.\033[0m\n' "$1"; exit 1; }
get()  { curl -fsSL -A "$UA" -o "$2" "$1"; }
unz()  { if command -v ditto >/dev/null 2>&1; then ditto -x -k "$1" "$2"; else mkdir -p "$2" && unzip -q -o "$1" -d "$2"; fi; }
copy_one() { mkdir -p "$(dirname "$2")" && cp "$1" "$2"; }

app_dir() { if [ -w /Applications ]; then echo /Applications; else mkdir -p "$HOME/Applications"; echo "$HOME/Applications"; fi; }
has_app() { [ -d "/Applications/$1.app" ] || [ -d "$HOME/Applications/$1.app" ]; }
install_dmg() { # url appname
  local dmg="$TMP/$2.dmg" mnt="$TMP/mnt-$2"
  get "$1" "$dmg" || return 1
  mkdir -p "$mnt"
  yes | hdiutil attach -nobrowse -noautoopen -mountpoint "$mnt" "$dmg" >/dev/null 2>&1 || return 1
  local src; src="$(find "$mnt" -maxdepth 1 -name "*.app" | head -1)"
  [ -n "$src" ] && cp -R "$src" "$(app_dir)/"
  hdiutil detach "$mnt" -quiet >/dev/null 2>&1 || true
  [ -n "$src" ]
}

printf '\n\033[33m  ================================\n       Your brain  -  setup\n  ================================\033[0m\n'
[ "$DRY" = "1" ] && warn "DRY RUN: nothing will be installed or opened"

# 1. Obsidian
say "Step 1 of 6: Obsidian"
if has_app Obsidian; then ok "Obsidian is already installed"
elif [ "$DRY" = "1" ]; then ok "dry run: skipped"
else
  echo "   downloading Obsidian..."
  url="$(curl -fsSL -A "$UA" 'https://api.github.com/repos/obsidianmd/obsidian-releases/releases?per_page=10' | grep -o '"browser_download_url": *"[^"]*\.dmg"' | head -1 | sed 's/.*"\(https[^"]*\)"/\1/')"
  [ -n "$url" ] || fail "could not find the Obsidian installer"
  install_dmg "$url" Obsidian && ok "Obsidian installed" || warn "Could not install Obsidian. Download it from obsidian.md/download"
fi

# 2. Claude desktop (includes Claude Code)
say "Step 2 of 6: Claude (desktop app with Claude Code)"
if has_app Claude; then ok "Claude is already installed"
elif [ "$DRY" = "1" ]; then ok "dry run: skipped"
else
  echo "   downloading Claude..."
  install_dmg "https://claude.ai/api/desktop/darwin/universal/dmg/latest/redirect" Claude && ok "Claude installed" || warn "Could not install Claude. Download it from claude.com/download"
fi

# 3. The brain folder + the agent kit. Her own files are never touched; the kit's skills are always refreshed.
say "Step 3 of 6: your brain folder"
mkdir -p "$VAULT" || fail "could not create $VAULT"
get "$BASE/kit.zip" "$TMP/kit.zip" || fail "could not download the brain kit"
unz "$TMP/kit.zip" "$TMP/kit" || fail "could not open the brain kit"
added=0
while IFS= read -r -d '' f; do
  rel="${f#"$TMP/kit"/}"
  dest="$VAULT/$rel"
  case "$rel" in
    .claude/skills/*) copy_one "$f" "$dest" || fail "could not copy $rel" ;;
    *) if [ ! -e "$dest" ]; then copy_one "$f" "$dest" || fail "could not copy $rel"; added=$((added+1)); fi ;;
  esac
done < <(find "$TMP/kit" -type f -print0)
ok "folder ready: $VAULT ($added new files, nothing of yours was changed)"

# 4. Skills for Obsidian formats (MIT, github.com/kepano/obsidian-skills)
say "Step 4 of 6: skills"
if get "https://github.com/kepano/obsidian-skills/archive/refs/heads/main.zip" "$TMP/os.zip" && unz "$TMP/os.zip" "$TMP/os"; then
  src="$(find "$TMP/os" -mindepth 1 -maxdepth 1 -type d ! -name '__MACOSX' | head -1)"
  for name in obsidian-markdown json-canvas obsidian-bases; do
    if [ -d "$src/skills/$name" ]; then
      mkdir -p "$VAULT/.claude/skills/$name"
      cp -R "$src/skills/$name/." "$VAULT/.claude/skills/$name/"
      [ -f "$src/LICENSE" ] && cp "$src/LICENSE" "$VAULT/.claude/skills/$name/LICENSE"
    fi
  done
  ok "ingest, ask-me, write-in-my-voice, obsidian-markdown, json-canvas, obsidian-bases"
else
  warn "Obsidian format skills were not added (the brain still works)"
fi

# 5. Her brain: the newest zip in Downloads with "המוח" in its name. Re-running with a newer zip updates it.
say "Step 5 of 6: your brain"
DL="${BRAIN_DOWNLOADS:-$HOME/Downloads}"
bz="$(ls -t "$DL/"*"$BRAIN_WORD"*.zip 2>/dev/null | head -1)"
if [ -n "$bz" ]; then
  unz "$bz" "$TMP/brain" || fail "could not open your brain file"
  broot="$TMP/brain"
  if [ "$(find "$broot" -mindepth 1 -maxdepth 1 ! -name '__MACOSX' | wc -l | tr -d ' ')" = "1" ]; then
    only="$(find "$broot" -mindepth 1 -maxdepth 1 ! -name '__MACOSX' | head -1)"
    [ -d "$only" ] && broot="$only"
  fi
  BAK="$VAULT/$BAK_NAME/$(date '+%Y-%m-%d %H%M')"
  n=0; same=0; saved=0
  while IFS= read -r -d '' f; do
    rel="${f#"$broot"/}"
    dest="$VAULT/$rel"
    if [ -f "$dest" ]; then
      if cmp -s "$f" "$dest"; then same=$((same+1)); continue; fi
      copy_one "$dest" "$BAK/$rel" || fail "could not back up $rel"
      saved=$((saved+1))
    fi
    copy_one "$f" "$dest" || fail "could not copy $rel"
    n=$((n+1))
  done < <(find "$broot" -type f ! -path '*/__MACOSX/*' ! -name '.DS_Store' -print0)
  ok "your brain is inside: $(basename "$bz") ($n files copied, $same already up to date)"
  [ "$saved" -gt 0 ] && ok "$saved files you had changed were saved first in: $BAK"
else
  warn "No brain file in Downloads yet. Save the file you got (its name has the word brain in Hebrew) to Downloads and run this line again."
fi
mkdir -p "$VAULT/$RAW_NAME/$MAT_NAME"

# 6. Open it as an Obsidian vault
say "Step 6 of 6: connecting the folder to Obsidian"
CFG="$HOME/Library/Application Support/obsidian/obsidian.json"
[ "$DRY" = "1" ] && CFG="$TMP/obsidian.json"
cat > "$TMP/reg.js" <<'JXA'
ObjC.import('Foundation');
function run(argv) {
  var cfg = argv[0], vault = argv[1], fm = $.NSFileManager.defaultManager, data = { vaults: {} };
  if (fm.fileExistsAtPath(cfg)) {
    var s = $.NSString.stringWithContentsOfFileEncodingError(cfg, $.NSUTF8StringEncoding, null);
    try { data = JSON.parse(ObjC.unwrap(s)); } catch (e) { data = { vaults: {} }; }
  }
  if (!data.vaults) data.vaults = {};
  var id = null;
  for (var k in data.vaults) { if (data.vaults[k].path === vault) { id = k; } else { data.vaults[k].open = false; } }
  if (!id) { id = ''; var hex = '0123456789abcdef'; for (var i = 0; i < 16; i++) id += hex[Math.floor(Math.random() * 16)]; }
  data.vaults[id] = { path: vault, ts: Date.now(), open: true };
  fm.createDirectoryAtPathWithIntermediateDirectoriesAttributesError(cfg.replace(/\/[^\/]+$/, ''), true, $(), null);
  $(JSON.stringify(data)).writeToFileAtomicallyEncodingError(cfg, true, $.NSUTF8StringEncoding, null);
  return id;
}
JXA
osascript -l JavaScript "$TMP/reg.js" "$CFG" "$VAULT" >/dev/null 2>&1 && ok "connected" || warn "Open Obsidian and choose 'Open folder as vault' > $VAULT_NAME"
pgrep -x Obsidian >/dev/null 2>&1 && [ "$DRY" != "1" ] && warn "Obsidian was already open. If your brain does not show, quit Obsidian and open it again."

if [ "$DRY" = "1" ]; then
  ok "dry run finished. Vault: $VAULT  Config: $CFG"
else
  open -a Obsidian 2>/dev/null || true
  open "$BASE/?installed=1#start" 2>/dev/null || true
fi

printf '\n\033[33m  ======================================================\033[0m\n'
printf '\033[32m   All set. Your brain is in this folder:\n   %s\n   Next: open Claude > Code > + New session > choose that folder.\n   The page that just opened in your browser shows what to write.\033[0m\n' "$VAULT"
printf '\033[33m  ======================================================\033[0m\n'
