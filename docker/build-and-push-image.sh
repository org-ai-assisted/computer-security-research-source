#!/bin/bash
# shellcheck disable=SC2154  # OWNER/GH_TOKEN/GH_ACTOR/GITHUB_STEP_SUMMARY: workflow env

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@kicksecure.com>
## See the file COPYING for copying conditions.

## AI-Assisted

## Build the pinned CSR toolchain image and push it to the PUBLIC GHCR package.
## Called by .github/workflows/build-image.yml (which supplies the env below).
## Prints the pushed @sha256 digest to paste into docker/image.ref.
##
## Env: GH_TOKEN (packages:write), GH_ACTOR (github.actor), OWNER
## (github.repository_owner), GITHUB_STEP_SUMMARY.

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace
shopt -s inherit_errexit
shopt -s shift_verbose
export LC_ALL=C

owner_lc="${OWNER,,}"
image="ghcr.io/${owner_lc}/csr-build-toolchain"

printf '%s' "${GH_TOKEN}" \
   | docker login ghcr.io --username "${GH_ACTOR}" --password-stdin
docker build --tag "${image}:latest" --file docker/Dockerfile docker
docker push "${image}:latest"

digest="$(docker inspect --format='{{index .RepoDigests 0}}' "${image}:latest")"
printf '%s\n' "pushed ${digest}"
{
   printf '%s\n' "Toolchain image pushed."
   printf '%s\n' ""
   printf '%s\n' "Update docker/image.ref to:"
   printf '%s\n' ""
   printf '%s\n' "    ${digest}"
} >> "${GITHUB_STEP_SUMMARY}"
