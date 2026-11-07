#!/bin/sh
# Builds the .deb in an elementary OS container (ghcr.io/elementary/docker),
# from a checkout at $PWD, against libghostty-gtk's latest release. Leaves it
# in ./dist. Used by .github/workflows/ci.yml.
set -eu

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
  ca-certificates curl jq git devscripts equivs lintian >/dev/null

# libghostty-gtk: the debs in $LIBGHOSTTY_GTK_DEBS if set (a local build),
# else the latest release's. The token only raises the API rate limit; the
# release is public.
if [ -n "${LIBGHOSTTY_GTK_DEBS:-}" ]; then
  deps=$LIBGHOSTTY_GTK_DEBS
else
  api=https://api.github.com/repos/arsfeld/libghostty-gtk/releases/latest
  auth=${GITHUB_TOKEN:+Authorization: Bearer $GITHUB_TOKEN}
  deps=$(mktemp -d)
  curl -fsSL ${auth:+-H "$auth"} "$api" \
    | jq -r '.assets[] | select(.name | endswith(".deb")) | .browser_download_url' \
    | while read -r url; do curl -fsSL -o "$deps/$(basename "$url")" "$url"; done
fi
ls "$deps"/libghostty-gtk-dev_*.deb >/dev/null
apt-get install -y -qq "$deps"/*.deb >/dev/null

# Each build's version sorts after the last, and after a rebase onto a new
# elementary release: upstream version, commit date, commit.
upstream=$(sed -n "s/^ *version: '\([^']*\)',\$/\1/p" meson.build | head -n1)
# Commit time in UTC to the second: same-day builds must not sort by hash.
date=$(TZ=UTC git log -1 --format=%cd --date=format-local:%Y%m%d%H%M%S)
sha=$(git rev-parse --short=8 HEAD)
version="$upstream+ghostty.git$date.$sha"
DEBEMAIL="alex@rosenfeld.one" DEBFULLNAME="Alexandre Rosenfeld" \
  dch --newversion "$version" --distribution noble --force-distribution \
  "Build of $(git rev-parse HEAD)."

mk-build-deps --install --remove --tool 'apt-get -y -qq --no-install-recommends' debian/control >/dev/null
dpkg-buildpackage -b -us -uc

mkdir -p dist
mv ../*.deb ../*.buildinfo ../*.changes dist/
echo "$version" > dist/VERSION

lintian --allow-root --info dist/*.deb || echo "lintian reported issues (not fatal)"
