#!/usr/bin/env bash
set -u

MODE="${1:-}"
WT="${2:-}"
MUT="${3:-}"
TEST_TIMEOUT="${RB_TEST_TIMEOUT:-600}"
READY_TIMEOUT="${RB_READY_TIMEOUT:-1800}"
BOM=$'\xEF\xBB\xBF'

die() {
  echo "red-green: $*" >&2
  exit 90
}

is_abs() {
  case "$1" in
    /*|[A-Za-z]:/*|[A-Za-z]:\\*) return 0 ;;
    *) return 1 ;;
  esac
}

[ -n "$WT" ] || die "WT vazio"
[ -n "$MUT" ] || die "MUT vazio"
is_abs "$WT" || die "WT precisa ser caminho absoluto: $WT"
is_abs "$MUT" || die "MUT precisa ser caminho absoluto: $MUT"
[ -f "$WT/../.revisar-branch" ] || die "WT fora de um diretório criado pela skill (sem .revisar-branch): $WT"
[ -d "$MUT" ] || die "MUT não existe: $MUT"
cd "$WT" || die "cd falhou: $WT"
[ "$(git rev-parse --git-dir 2>/dev/null)" != "$(git rev-parse --git-common-dir 2>/dev/null)" ] || die "WT é o worktree principal: $WT"

LOG="$MUT/log"
STATUS="$LOG/status"
mkdir -p "$LOG"

if command -v timeout > /dev/null 2>&1; then
  run_test() { timeout -k 30 "$TEST_TIMEOUT" dotnet test "$@" < /dev/null; }
else
  run_test() { dotnet test "$@" < /dev/null; }
fi

baseline() { git diff HEAD | git hash-object --stdin; }

clean_field() {
  local v="${1%$'\r'}"
  printf '%s' "${v#"$BOM"}"
}

mutate() {
  local id="$1" proj="$2" filter="$3" path="$4" tag="$5"
  if [ -z "$id" ] || [ -z "$proj" ] || [ -z "$filter" ] || [ -z "$path" ]; then
    echo "${id:-?}$tag setup=FAIL campo-vazio" >> "$STATUS"
    return 0
  fi
  if [ ! -f "$MUT/$id.file" ] || [ ! -f "$path" ] || [ ! -e "$proj" ]; then
    echo "$id$tag setup=FAIL arquivo-ausente" >> "$STATUS"
    return 0
  fi

  local base orig_sum b t
  base="$(baseline)"
  orig_sum="$(git hash-object "$path")"
  if ! cp "$path" "$MUT/$id.orig"; then
    echo "$id$tag setup=FAIL cp-orig" >> "$STATUS"
    return 0
  fi
  if ! cp "$MUT/$id.file" "$path"; then
    cp "$MUT/$id.orig" "$path"
    echo "$id$tag setup=FAIL cp-mut" >> "$STATUS"
    return 0
  fi
  if [ "$(git hash-object "$path")" = "$orig_sum" ]; then
    echo "$id$tag mut=NOOP" >> "$STATUS"
    return 0
  fi

  dotnet build "$proj" --no-restore < /dev/null > "$LOG/$id$tag.build.txt" 2>&1
  b=$?
  t=skip
  if [ "$b" -eq 0 ]; then
    run_test "$proj" --no-build --filter "$filter" --logger "console;verbosity=normal" > "$LOG/$id$tag.test.txt" 2>&1
    t=$?
    [ "$t" -eq 124 ] && t=timeout
  fi

  cp "$MUT/$id.orig" "$path"
  if [ "$(git hash-object "$path")" != "$orig_sum" ] || [ "$(baseline)" != "$base" ]; then
    echo "$id$tag restore=FAIL" >> "$STATUS"
    exit 92
  fi
  echo "$id$tag build=$b test=$t" >> "$STATUS"
}

restore_build() {
  dotnet restore "$SLN" < /dev/null > "$LOG/restore.txt" 2>&1
  local r=$?
  echo "restore=$r" >> "$STATUS"
  [ "$r" -eq 0 ] || return 1
  dotnet build "$SLN" --no-restore < /dev/null > "$LOG/build.txt" 2>&1
  local b=$?
  echo "build=$b" >> "$STATUS"
  [ "$b" -eq 0 ]
}

case "$MODE" in
  suite)
    SLN="${4:-}"
    [ -n "$SLN" ] || die "SLN vazio"
    : > "$STATUS"
    if restore_build; then
      run_test "$SLN" --no-build > "$LOG/final-test.txt" 2>&1
      f=$?
      [ "$f" -eq 124 ] && f=timeout
      echo "final-test=$f" >> "$STATUS"
    fi
    echo "done" >> "$STATUS"
    ;;

  run)
    SLN="${4:-}"
    GREEN_FILTER="${5:-}"
    [ -n "$SLN" ] || die "SLN vazio"
    [ -n "$GREEN_FILTER" ] || die "filtro green vazio"
    : > "$STATUS"

    if ! restore_build; then
      echo "mutations=skipped" >> "$STATUS"
      echo "done" >> "$STATUS"
      exit 0
    fi

    run_test "$SLN" --no-build --filter "$GREEN_FILTER" --logger "console;verbosity=normal" > "$LOG/green.txt" 2>&1
    g=$?
    [ "$g" -eq 124 ] && g=timeout
    echo "green=$g" >> "$STATUS"

    waited=0
    while [ ! -f "$MUT/READY" ] && [ "$waited" -lt "$READY_TIMEOUT" ]; do
      sleep 2
      waited=$((waited + 2))
    done
    if [ ! -f "$MUT/READY" ]; then
      echo "ready=timeout" >> "$STATUS"
      exit 91
    fi

    if [ -f "$MUT/manifest.tsv" ]; then
      while IFS=$'\t' read -r -u 3 id proj filter path || [ -n "${id:-}" ]; do
        id="$(clean_field "${id:-}")"
        proj="$(clean_field "${proj:-}")"
        filter="$(clean_field "${filter:-}")"
        path="$(clean_field "${path:-}")"
        [ -z "$id$proj$filter$path" ] && continue
        mutate "$id" "$proj" "$filter" "$path" ""
      done 3< "$MUT/manifest.tsv"
    fi

    dotnet build "$SLN" --no-restore < /dev/null > "$LOG/final-build.txt" 2>&1
    echo "final-build=$?" >> "$STATUS"
    run_test "$SLN" --no-build > "$LOG/final-test.txt" 2>&1
    f=$?
    [ "$f" -eq 124 ] && f=timeout
    echo "final-test=$f" >> "$STATUS"
    echo "done" >> "$STATUS"
    ;;

  one)
    TARGET="${4:-}"
    [ -n "$TARGET" ] || die "id vazio"
    [ -f "$MUT/manifest.tsv" ] || die "manifest.tsv ausente"
    found=0
    while IFS=$'\t' read -r -u 3 id proj filter path || [ -n "${id:-}" ]; do
      id="$(clean_field "${id:-}")"
      [ "$id" = "$TARGET" ] || continue
      found=1
      mutate "$id" "$(clean_field "${proj:-}")" "$(clean_field "${filter:-}")" "$(clean_field "${path:-}")" ".retry"
      break
    done 3< "$MUT/manifest.tsv"
    [ "$found" -eq 1 ] || die "id não encontrado no manifesto: $TARGET"
    tail -n 1 "$STATUS"
    ;;

  *)
    die "uso: red-green.sh run <WT> <MUT> <SLN> <filtro> | red-green.sh one <WT> <MUT> <id> | red-green.sh suite <WT> <MUT> <SLN>"
    ;;
esac
