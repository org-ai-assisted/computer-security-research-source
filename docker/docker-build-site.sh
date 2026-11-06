#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@kicksecure.com>
## See the file COPYING for copying conditions.

## AI-Assisted

## Build journal-maker's site output inside the pinned toolchain image. Used by
## BOTH bin/csr-build (local, in the sandbox) and .github/workflows/pages.yml
## (deploy, on the runner), so the PDF/docx bytes are produced by the SAME
## toolchain and match the committed .sha512 bit-for-bit.
##
## Registry-free (no GHCR): the image is BUILT from docker/Dockerfile here and
## cached per host (sandbox /var/lib/docker; the CI runner per run). The toolchain
## is frozen by the base @sha256 digest in the Dockerfile; within a publish window
## both hosts build the same bytes, and a drift (e.g. a stale re-deploy after the
## archive moved) is caught loudly by --verify-sha at deploy, never shipped.
##
## Usage:
##   docker-build-site.sh <journal-maker-dir> <content-dir> <out-dir> [journal-maker build args...]
##
## Builds into <out-dir>/_site (a SUBDIR of the mounted dir, never the mount
## POINT -- journal-maker rmtree's --out, and a bind-mount point cannot be removed
## from inside the container). Extra args pass through, e.g. '--pdf-only
## --verify-sha' for the deploy.

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace
shopt -s inherit_errexit
shopt -s shift_verbose
export LC_ALL=C

if [ "$#" -lt 3 ]; then
   printf '%s\n' "usage: $0 <journal-maker-dir> <content-dir> <out-dir> [build args...]" >&2
   exit 64
fi

journal_maker="$1"
content="$2"
out="$3"
shift 3

image='csr-build-toolchain:latest'
docker_dir="$(dirname -- "$(readlink --canonicalize -- "$0")")"

## ALWAYS docker build (not build-if-missing): the layer cache makes an unchanged
## Dockerfile a fast no-op, while a Dockerfile change (a toolchain bump) correctly
## rebuilds -- a build-if-present check would pin a stale cached image and silently
## defeat the bump. The image is fully defined by docker/Dockerfile.
printf '%s\n' "docker-build-site: building ${image} from ${docker_dir}/Dockerfile ..."
docker build --tag "${image}" --file "${docker_dir}/Dockerfile" "${docker_dir}"

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
