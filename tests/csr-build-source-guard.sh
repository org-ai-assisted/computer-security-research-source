#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@kicksecure.com>
## See the file COPYING for copying conditions.

## AI-Assisted

## Regression test for csr-build's uncommitted-source guard + TOCTOU re-check.
##
## The guard must:
##   A. REFUSE a dirty tracked render input (articles/pages/site.toml/web-tests).
##   E. REFUSE an untracked (never-added) render input.
##   B. PASS on a clean tree.
##   C. be SKIPPED under --no-commit.
##   J. NOT block a dirty NON-render file (bin/, docker/, CI workflow).
##   L. REFUSE a dirty pages/ render input.
##   M. REFUSE a dirty .github/web-tests.yml (copied into _site).
##   N. NOT block a dirty .github/workflows CI file.
##   H. REFUSE an untracked render input even under status.showUntrackedFiles=no.
## and the TOCTOU re-check must:
##   F. REFUSE when a source edit RACES the render (lands after the pre-build guard).
##
## Method: guard cases run the real bin/csr-build with the build tools pointed at
## a nonexistent path, so a guard PASS falls through to the "journal-maker not
## found" check while a guard FIRE stops at the guard. The TOCTOU case stubs the
## sandbox build (which fakes the pulled _site + a raced source edit). Canaries
## prove each guard is load-bearing on the pre-fix code.

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace
shopt -s inherit_errexit
shopt -s shift_verbose
export LC_ALL=C

test_dir="$(dirname -- "$(readlink --canonicalize -- "$0")")"
repo_root="$(dirname -- "${test_dir}")"
csr_build="${repo_root}/bin/csr-build"
guard_msg="uncommitted source changes"
tool_check_msg="journal-maker not found"
recheck_msg="sources changed during the build"
pushed_msg="committed + pushed"
fails=0
build_out=""
build_rc=0

if [ ! -x "${csr_build}" ]; then
   printf '%s\n' "test: csr-build not executable at ${csr_build}" >&2
   exit 1
fi

contains() {
   [ "${1#*"$2"}" != "$1" ]
}

make_fixture() {
   local fixture
   fixture="$(mktemp --directory)"
   git -C "${fixture}" init --quiet
   git -C "${fixture}" config user.email test@example.invalid
   git -C "${fixture}" config user.name "csr test"
   mkdir -- "${fixture}/bin" "${fixture}/articles"
   cp -- "${1:-${csr_build}}" "${fixture}/bin/csr-build"
   printf '%s\n' 'name = "x"' > "${fixture}/site.toml"
   printf '%s\n' 'paper source' > "${fixture}/articles/paper.md"
   git -C "${fixture}" -c core.hooksPath=/dev/null add --all
   git -C "${fixture}" -c core.hooksPath=/dev/null commit --quiet --message init
   printf '%s\n' "${fixture}"
}

run_build() {
   ## Build tools missing on purpose: a guard PASS then halts at the tool check.
   local fixture="$1"
   shift
   build_rc=0
   build_out="$(
      CSR_JOURNAL_MAKER=/nonexistent \
      CSR_DIST_AI=/nonexistent \
      CSR_ARTIFACTS=/nonexistent \
      CSR_IMAGE=x \
      "${fixture}/bin/csr-build" "$@" 2>&1
   )" || build_rc=$?
}

expect_guard_fired() {
   local label="$1"
   if [ "${build_rc}" -ne 1 ]; then
      printf '%s\n' "FAIL: ${label} -- expected rc 1, got ${build_rc}" >&2
      fails=$((fails + 1))
   fi
   if ! contains "${build_out}" "${guard_msg}"; then
      printf '%s\n' "FAIL: ${label} -- expected the guard message, got: ${build_out}" >&2
      fails=$((fails + 1))
   fi
}

expect_guard_passed() {
   local label="$1"
   if contains "${build_out}" "${guard_msg}"; then
      printf '%s\n' "FAIL: ${label} -- guard fired but should have passed, got: ${build_out}" >&2
      fails=$((fails + 1))
   fi
   if [ "${build_rc}" -ne 1 ] || ! contains "${build_out}" "${tool_check_msg}"; then
      printf '%s\n' "FAIL: ${label} -- expected to reach the tool check (rc 1 + '${tool_check_msg}'), got rc ${build_rc}: ${build_out}" >&2
      fails=$((fails + 1))
   fi
}

## A. dirty tracked source, committing -> guard FIRES
fixture_a="$(make_fixture)"
printf '%s\n' 'edited paper source' > "${fixture_a}/articles/paper.md"
run_build "${fixture_a}"
expect_guard_fired "A: dirty source is refused"
safe-rm --recursive --force -- "${fixture_a}"

## B. clean tree, committing -> guard PASSES
fixture_b="$(make_fixture)"
run_build "${fixture_b}"
expect_guard_passed "B: clean tree passes the guard"
safe-rm --recursive --force -- "${fixture_b}"

## C. dirty source, --no-commit -> guard SKIPPED
fixture_c="$(make_fixture)"
printf '%s\n' 'edited paper source' > "${fixture_c}/articles/paper.md"
run_build "${fixture_c}" --no-commit
expect_guard_passed "C: --no-commit skips the guard"
safe-rm --recursive --force -- "${fixture_c}"

## E. untracked (never-added) render input, committing -> guard FIRES
fixture_e="$(make_fixture)"
printf '%s\n' '# brand new article' > "${fixture_e}/articles/newpaper.md"
run_build "${fixture_e}"
expect_guard_fired "E: an untracked new source file is refused"
safe-rm --recursive --force -- "${fixture_e}"

## H. untracked render input under status.showUntrackedFiles=no -> still FIRES
fixture_h="$(make_fixture)"
git -C "${fixture_h}" config status.showUntrackedFiles no
printf '%s\n' '# sneaked-in article' > "${fixture_h}/articles/sneak.md"
run_build "${fixture_h}"
expect_guard_fired "H: untracked source under showUntrackedFiles=no is refused"
safe-rm --recursive --force -- "${fixture_h}"

## I. CANARY: strip --untracked-files=all -> the config hides the untracked source
unflagged="$(mktemp)"
sed 's/ --untracked-files=all//' "${csr_build}" > "${unflagged}"
chmod +x -- "${unflagged}"
if cmp --silent -- "${csr_build}" "${unflagged}"; then
   printf '%s\n' "FAIL: I: canary could not strip --untracked-files=all" >&2
   fails=$((fails + 1))
fi
fixture_i="$(make_fixture "${unflagged}")"
git -C "${fixture_i}" config status.showUntrackedFiles no
printf '%s\n' '# sneaked-in article' > "${fixture_i}/articles/sneak.md"
run_build "${fixture_i}"
expect_guard_passed "I: without -uall the config hides the untracked source"
safe-rm --recursive --force -- "${fixture_i}"
safe-rm --force -- "${unflagged}"

## J. dirty BUILD SCRIPT is not a render input -> must NOT block
fixture_j="$(make_fixture)"
printf '%s\n' '## sibling WIP edit' >> "${fixture_j}/bin/csr-build"
run_build "${fixture_j}"
expect_guard_passed "J: a dirty build script does not block a content publish"
safe-rm --recursive --force -- "${fixture_j}"

## K. CANARY: a broad scope (whole tree) makes the dirty build script block --
## proves the positive render-input list is what lets a non-render edit through.
unscoped="$(mktemp)"
sed "s|articles pages site.toml .github/web-tests.yml|.|" "${csr_build}" > "${unscoped}"
chmod +x -- "${unscoped}"
if cmp --silent -- "${csr_build}" "${unscoped}"; then
   printf '%s\n' "FAIL: K: canary could not rewrite the render-input pathspec" >&2
   fails=$((fails + 1))
fi
fixture_k="$(make_fixture "${unscoped}")"
printf '%s\n' '## sibling WIP edit' >> "${fixture_k}/bin/csr-build"
run_build "${fixture_k}"
expect_guard_fired "K: the broad scope blocks a dirty build script"
safe-rm --recursive --force -- "${fixture_k}"
safe-rm --force -- "${unscoped}"

## L. dirty pages/ render input -> FIRES
fixture_l="$(make_fixture)"
mkdir -- "${fixture_l}/pages"
printf '%s\n' '# new page' > "${fixture_l}/pages/about.md"
run_build "${fixture_l}"
expect_guard_fired "L: a dirty pages/ render input is refused"
safe-rm --recursive --force -- "${fixture_l}"

## M. dirty .github/web-tests.yml (copied into _site) -> FIRES
fixture_m="$(make_fixture)"
mkdir -- "${fixture_m}/.github"
printf '%s\n' 'policies: [csr]' > "${fixture_m}/.github/web-tests.yml"
run_build "${fixture_m}"
expect_guard_fired "M: a dirty .github/web-tests.yml is refused"
safe-rm --recursive --force -- "${fixture_m}"

## N. dirty CI workflow is not a render input -> must NOT block
fixture_n="$(make_fixture)"
mkdir -- "${fixture_n}/.github" "${fixture_n}/.github/workflows"
printf '%s\n' '# WIP' > "${fixture_n}/.github/workflows/checks.yml"
run_build "${fixture_n}"
expect_guard_passed "N: a dirty CI workflow does not block a content publish"
safe-rm --recursive --force -- "${fixture_n}"

## F/G reach the commit path: stub the build tools + sandbox + artifacts repo.
fakebin="$(mktemp --directory)"
stub_root="$(mktemp --directory)"
tmp_home="$(mktemp --directory)"
stub_jm="${stub_root}/journal-maker"
stub_dist="${stub_root}/dist-ai"
stub_artifacts="${stub_root}/artifacts"

make_exit0_stub() {
   cat > "$1" <<'STUB'
#!/bin/bash
exit 0
STUB
   chmod +x -- "$1"
}

## Fake sandbox: 'exec' (preflight) is a no-op; 'run' (build) creates the pulled
## _site AND dirties a tracked source, simulating an edit that raced the render.
cat > "${fakebin}/sandbox" <<'SANDBOX'
#!/bin/bash
set -o errexit -o nounset -o pipefail
sub=""
pull=""
workdir=""
while [ "$#" -gt 0 ]; do
   case "$1" in
      exec|run) sub="$1"; shift ;;
      --pull) pull="$2"; shift 2 ;;
      --workdir) workdir="$2"; shift 2 ;;
      --) shift; break ;;
      *) shift ;;
   esac
done
if [ "${sub}" = "run" ]; then
   mkdir --parents -- "${pull}/_site"
   printf '%s\n' '<html></html>' > "${pull}/_site/index.html"
   printf '%s\n' 'raced edit during render' >> "${workdir}/articles/paper.md"
fi
exit 0
SANDBOX
chmod +x -- "${fakebin}/sandbox"

mkdir --parents -- "${stub_jm}/usr/bin" "${stub_dist}/usr/share/website-tests"
make_exit0_stub "${stub_jm}/usr/bin/journal-maker"
make_exit0_stub "${stub_dist}/usr/share/website-tests/check_site.py"
make_exit0_stub "${stub_dist}/usr/share/website-tests/check_svg_safety.py"

## artifacts repo stub: a git repo on master with _site/, hooks disabled, and two
## LOCAL bare remotes named like the real deploy home + mirror so the publish
## push (default CSR_ARTIFACTS_REMOTES) succeeds without a network.
bare_a="${stub_root}/bare-csr.git"
bare_b="${stub_root}/bare-org.git"
setup_artifacts_stub() {
   safe-rm --recursive --force -- "${stub_artifacts}" "${bare_a}" "${bare_b}"
   git init --quiet --bare "${bare_a}"
   git init --quiet --bare "${bare_b}"
   mkdir --parents -- "${stub_artifacts}/_site"
   git -C "${stub_artifacts}" init --quiet --initial-branch=master
   git -C "${stub_artifacts}" config core.hooksPath /dev/null
   git -C "${stub_artifacts}" config user.email test@example.invalid
   git -C "${stub_artifacts}" config user.name "csr test"
   git -C "${stub_artifacts}" remote add computer-security-research "${bare_a}"
   git -C "${stub_artifacts}" remote add org-ai-assisted "${bare_b}"
   printf '%s\n' '<html></html>' > "${stub_artifacts}/_site/placeholder.html"
   git -C "${stub_artifacts}" add --all
   git -C "${stub_artifacts}" commit --quiet --message init
   git -C "${stub_artifacts}" push --quiet computer-security-research master
   git -C "${stub_artifacts}" push --quiet org-ai-assisted master
}
setup_artifacts_stub

run_build_full() {
   local fixture="$1"
   build_rc=0
   build_out="$(
      PATH="${fakebin}:${PATH}" \
      HOME="${tmp_home}" \
      CSR_JOURNAL_MAKER="${stub_jm}" \
      CSR_DIST_AI="${stub_dist}" \
      CSR_ARTIFACTS="${stub_artifacts}" \
      CSR_IMAGE=x \
      "${fixture}/bin/csr-build" 2>&1
   )" || build_rc=$?
}

## F. a source edit RACES the render -> the post-build re-check FIRES, no publish.
fixture_f="$(make_fixture)"
run_build_full "${fixture_f}"
if [ "${build_rc}" -ne 1 ]; then
   printf '%s\n' "FAIL: F: raced edit -- expected rc 1, got ${build_rc}: ${build_out}" >&2
   fails=$((fails + 1))
fi
if ! contains "${build_out}" "${recheck_msg}"; then
   printf '%s\n' "FAIL: F: raced edit -- expected the re-check message, got: ${build_out}" >&2
   fails=$((fails + 1))
fi
if contains "${build_out}" "${pushed_msg}"; then
   printf '%s\n' "FAIL: F: raced edit -- published despite the race, got: ${build_out}" >&2
   fails=$((fails + 1))
fi
safe-rm --recursive --force -- "${fixture_f}"

## G. CANARY: the SAME race against a pre-fix csr-build (re-check stripped) must
## NOT refuse -- it commits + pushes (empty remote list -> no push, but the
## "committed + pushed" line prints).
stripped="$(mktemp)"
sed '/CANARY-RECHECK-START/,/CANARY-RECHECK-END/d' "${csr_build}" > "${stripped}"
chmod +x -- "${stripped}"
if cmp --silent -- "${csr_build}" "${stripped}"; then
   printf '%s\n' "FAIL: G: canary could not strip the re-check (sentinels missing?)" >&2
   fails=$((fails + 1))
fi
## reset the artifacts stub so the prior run's state does not interfere
setup_artifacts_stub
fixture_g="$(make_fixture "${stripped}")"
run_build_full "${fixture_g}"
if contains "${build_out}" "${recheck_msg}"; then
   printf '%s\n' "FAIL: G: canary -- pre-fix code must not run the re-check, got: ${build_out}" >&2
   fails=$((fails + 1))
fi
if ! contains "${build_out}" "${pushed_msg}"; then
   printf '%s\n' "FAIL: G: canary -- pre-fix code should commit+publish, got: ${build_out}" >&2
   fails=$((fails + 1))
fi
safe-rm --recursive --force -- "${fixture_g}"
safe-rm --force -- "${stripped}"
safe-rm --recursive --force -- "${fakebin}" "${stub_root}" "${tmp_home}"

if [ "${fails}" -eq 0 ]; then
   printf '%s\n' "csr-build-source-guard: all cases passed"
else
   printf '%s\n' "csr-build-source-guard: ${fails} case(s) failed" >&2
   exit 1
fi
