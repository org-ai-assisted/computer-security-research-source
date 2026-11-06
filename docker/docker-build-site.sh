#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@kicksecure.com>
## See the file COPYING for copying conditions.

## AI-Assisted

## Run journal-maker build inside the pinned toolchain image. Used by BOTH
## bin/csr-build (local, in the sandbox) and .github/workflows/pages.yml (deploy,
## on the runner) so the PDF/docx bytes are produced by the SAME toolchain and
## match the committed .sha512 bit-for-bit.
##
## Usage:
##   docker-build-site.sh <image> <journal-maker-dir> <content-dir> <out-dir> [journal-maker build args...]
##
## The site is built into <out-dir>/_site (a SUBDIR of the mounted dir, never the
## mount POINT -- journal-maker rmtree's --out, and a bind-mount point cannot be
## removed from inside the container). Extra args are passed through, e.g.
## '--pdf-only --verify-sha' for the deploy.

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace
shopt -s inherit_errexit
shopt -s shift_verbose
export LC_ALL=C

if [ "$#" -lt 4 ]; then
   printf '%s\n' "usage: $0 <image> <journal-maker-dir> <content-dir> <out-dir> [build args...]" >&2
   exit 64
fi

image="$1"
journal_maker="$2"
content="$3"
out="$4"
shift 4

## --network none: the build is offline (pandoc + pdflatex + local CSL); it also
## guarantees no network input can perturb the reproducible output.
## --user to the caller's uid so the written tree is not root-owned.
## container_home gives texlive/fontconfig a writable cache; the --user uid has no
## passwd home, so point HOME at the image's tmpfs.
## style-ok: no-tmp-hardcode -- container HOME on the image tmpfs, not a host temp path
container_home='/tmp'
docker run --rm --network none \
   --user "$(id -u):$(id -g)" \
   --env "HOME=${container_home}" \
   --env LC_ALL=C \
   --volume "${journal_maker}:/jm:ro" \
   --volume "${content}:/content:ro" \
   --volume "${out}:/work:rw" \
   --workdir /work \
   "${image}" \
   /jm/usr/bin/journal-maker build \
      --articles /content/articles \
      --journal /content/site.toml \
      --out /work/_site \
      "$@"
