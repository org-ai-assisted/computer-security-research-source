## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@kicksecure.com>
## See the file COPYING for copying conditions.

## AI-Assisted

## Pinned, reproducible toolchain image for the CSR previews site: pandoc +
## TeX Live + the webcheck python deps. Run BOTH locally (bin/csr-build, in the
## sandbox) and in the Pages deploy (pages.yml) so the PDF/docx bytes match
## bit-for-bit and the committed .sha512 describes the SERVED file.
##
## Reproducibility model: the toolchain is frozen by the built IMAGE, pinned by
## @sha256 digest in docker/image.ref -- BOTH sides pull that one digest, so they
## run byte-identical binaries. The image is built ONCE from the current Debian
## trixie archive (deb.debian.org -- reliable, unlike snapshot.debian.org which
## 503s under load), pushed to the public GHCR package, and rebuilt only on a
## deliberate toolchain bump (which re-mints the committed .sha512). Freezing via
## the shared image digest -- not apt snapshot pinning -- keeps every build
## reliable while staying reproducible across the two hosts.
##
## Re-resolve the base digest:
##   docker pull debian:trixie-slim
##   docker image inspect debian:trixie-slim --format '{{index .RepoDigests 0}}'
FROM debian:trixie-slim@sha256:a72b4433de1cf7d6bae0c4cee74d0547f58601a643b3375f070c51600d63b6b2

SHELL ["/bin/bash", "-o", "errexit", "-o", "nounset", "-o", "pipefail", "-c"]
ENV LC_ALL=C

## Ride out transient archive hiccups rather than failing a cold build.
RUN printf 'Acquire::Retries "6";\nAcquire::http::Timeout "60";\nAcquire::https::Timeout "60";\n' \
      > /etc/apt/apt.conf.d/80-csr-retries

## The toolchain. The texlive/pandoc/rsvg set is journal-maker's OWN runtime
## Depends (journal-maker debian/control -- the single source of truth; keep in
## sync with it, NOT with a hand-copied list). The python3-* set is the dist-ai
## webcheck deps (check_site / check_svg_safety), so those gates can run in the
## same image.
RUN apt-get update -qq \
   && apt-get install -y --no-install-recommends \
      pandoc \
      texlive-xetex \
      texlive-latex-recommended \
      texlive-fonts-recommended \
      texlive-publishers \
      texlive-plain-generic \
      lmodern \
      poppler-utils \
      qpdf \
      librsvg2-bin \
      citation-style-language-styles \
      python3-bs4 \
      python3-html5lib \
      python3-pil \
      python3-yaml \
      python3-defusedxml \
   && apt-get clean \
   && rm -rf /var/lib/apt/lists/*
