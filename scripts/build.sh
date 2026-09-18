#!/usr/bin/env bash
# Build PhosphorIDE and prove the build is worth having, on Linux.
#
#   bash scripts/build.sh              debug build + checks
#   bash scripts/build.sh --release    optimised, stripped
#   bash scripts/build.sh --no-checks  build only
#   bash scripts/build.sh --require-host   the host contract check may not skip
#
# The same three checks as scripts/build.ps1, for the same reasons, with one
# difference that matters here: --selftest CONSTRUCTS FORMS, and constructing an
# LCL form under gtk2 needs a display. On a headless machine that step is skipped
# rather than failed -- but it is announced, because a check that quietly does not
# run reads as a pass. Set DISPLAY (xvfb-run works) to get it back.
#
# timeout(1) wraps the selftest for the reason the Windows script uses a
# WaitForExit: a modal dialog is not an exit code, it is a process that never
# finishes.

set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bin="$root/bin"

release=0
checks=1
phosphor_repo=""
require_host=0
selftest_timeout=60

while [ $# -gt 0 ]; do
    case "$1" in
        --release) release=1 ;;
        --no-checks) checks=0 ;;
        --phosphor) shift; phosphor_repo="${1:-}" ;;
        --require-host) require_host=1 ;;
        --timeout) shift; selftest_timeout="${1:-60}" ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
    shift
done

fail() {
    echo ""
    echo "BUILD FAILED: $*" >&2
    exit 1
}

lazbuild="$(command -v lazbuild || true)"
if [ -z "$lazbuild" ]; then
    for candidate in /usr/bin/lazbuild /usr/local/bin/lazbuild "$HOME/lazarus/lazbuild"; do
        [ -x "$candidate" ] && lazbuild="$candidate" && break
    done
fi
[ -n "$lazbuild" ] || fail 'lazbuild not found. Install Lazarus (apt install lazarus), or put lazbuild on PATH.'

mode="Default"
[ "$release" -eq 1 ] && mode="Release"

echo "lazbuild: $lazbuild"
echo "mode:     $mode"
echo ""

# ---------------------------------------------------------------- the build --

build_project() {
    local project="$1" build_mode="$2" out
    echo "building $project ($build_mode)"
    # -B for the same reason as on Windows: a stale .lfm resource hides exactly
    # the mismatch the selftest is here to catch.
    out="$("$lazbuild" -B "--build-mode=$build_mode" "$project" 2>&1)"
    local rc=$?
    local bad
    bad="$(printf '%s\n' "$out" | grep -E '(Error|Fatal|Warning|Note):' || true)"
    if [ -n "$bad" ]; then
        printf '  %s\n' "$bad"
    fi
    if [ $rc -ne 0 ] || [ -n "$bad" ]; then
        fail "$project did not build cleanly (zero errors, warnings and notes is the bar)."
    fi
    echo "  ok"
}

build_project "$root/src/phosphoride.lpi" "$mode"
build_project "$root/tests/phosphoridetest.lpi" "Default"
build_project "$root/tests/phosphorcontract.lpi" "Default"

exe="$bin/phosphoride"
test_exe="$bin/phosphoridetest"
contract_exe="$bin/phosphorcontract"
[ -x "$exe" ] || fail "no binary at $exe"

if [ "$checks" -eq 0 ]; then
    echo ""
    echo "built $exe (checks skipped)"
    exit 0
fi

# --------------------------------------------------------------- the checks --

echo ""
echo "unit checks"
"$test_exe" || fail "$? unit check(s) failed."

# THE ONE COUPLING BETWEEN THE TWO REPOSITORIES THAT HAD NO CHECK. Everything
# above tests uphosphormsg.pas against strings THIS repository wrote down; this
# runs the actual binary and asserts the shapes it really emits. Exit 77 is its
# skip, announced by the program itself so it exists however it was invoked --
# the same discipline as the selftest skip below.
echo ""
echo "host contract"
if [ "$require_host" -eq 1 ]; then
    "$contract_exe" --require-host
else
    "$contract_exe"
fi
rc=$?
if [ $rc -eq 77 ]; then
    :   # already announced itself, in its own words
elif [ $rc -ne 0 ]; then
    fail "$rc shape(s) no longer match the phosphor binary."
fi

echo ""
echo "form streaming (--selftest)"
if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
    echo "  SKIPPED: no display. Constructing an LCL form needs one under gtk2."
    echo "  Run under xvfb-run to include this check:"
    echo "    xvfb-run -a bash scripts/build.sh"
else
    report="${TMPDIR:-/tmp}/phosphoride-selftest.txt"
    rm -f "$report"
    if ! timeout "$selftest_timeout" "$exe" --selftest "$report"; then
        rc=$?
        [ -f "$report" ] && sed 's/^/  /' "$report"
        if [ $rc -eq 124 ]; then
            echo "  the selftest never exited." >&2
            echo "  A GUI binary that hangs instead of answering is almost always a dialog" >&2
            echo "  nobody can dismiss: an .lfm/.pas mismatch is the usual cause." >&2
            fail "selftest timed out."
        fi
        fail "selftest exit code $rc."
    fi
    [ -f "$report" ] && sed 's/^/  /' "$report"
    echo "  ok"
fi

# The generated tables copy facts out of another repository, so the check is only
# meaningful where that repository is.
if [ -z "$phosphor_repo" ]; then
    for guess in "$(dirname "$root")/Phosphor" "$HOME/Phosphor"; do
        [ -d "$guess/engine/libs" ] && phosphor_repo="$guess" && break
    done
fi

echo ""
echo "generated language tables"
if [ -z "$phosphor_repo" ] || [ ! -d "$phosphor_repo/engine/libs" ]; then
    echo "  SKIPPED: no Phosphor checkout found."
    echo "  Pass --phosphor <path> to check that src/core/uphosphorlang.pas still"
    echo "  matches the sources it was generated from."
elif ! command -v python3 >/dev/null 2>&1; then
    echo "  SKIPPED: python3 not found."
else
    python3 "$root/tools/gen-keywords.py" "$phosphor_repo" --check \
        || fail 'uphosphorlang.pas is stale -- rerun tools/gen-keywords.py.'
fi

# The other generated unit; see build.ps1 for why this one needs no repository.
echo ""
echo "generated icons"
if ! command -v python3 >/dev/null 2>&1; then
    echo "  SKIPPED: python3 not found."
else
    python3 "$root/tools/gen-icons.py" --check \
        || fail 'uphosphoricons.pas is not what tools/gen-icons.py writes.'
fi

echo ""
echo "citations"
if ! command -v python3 >/dev/null 2>&1; then
    echo "  SKIPPED: python3 not found."
else
    python3 "$root/tools/check-citations.py" \
        || fail 'a file:line citation no longer points at what it claimed.'
fi

echo ""
echo "built and checked: $exe"
