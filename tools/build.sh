#!/bin/sh
# tools/build.sh <site> - the apt repository https://deb.azsupport.dev (aZ, 25.11.2026:
# «давай тогда уж и свой репозиторий убунты сделаем? чтобы по apt и ставилось и
# обновлялось?», «а может репозиторий уже не ports делать? а apt?»; apt.azsupport.com
# until 17:51 that day: «может зря назвали домен apt ? может надо было .deb раз файлы там
# deb?»; deb.azsupport.com until 18:36: «пакеты на azsupport.dev ... делаем так»): the Debian packages
# that the workflow ubuntu.yml of azsupport/ports publishes in its releases
# az-ubuntu<24|22>-amd64-<v3|v2>, as a repository of the usual layout:
#
#   pool/<v3|v2>/a/<package>/<package>_<version>_amd64.deb
#   dists/<noble|jammy>/<v3|v2>/binary-amd64/Packages, Packages.gz, Packages.xz
#   dists/<noble|jammy>/Release, InRelease, Release.gpg   signed with APT_SIGNING_KEY
#   azsupport.gpg, azsupport.asc                          the public key (signed-by)
#   index.html                                            how to install, for people
#
# A suite per release of Ubuntu (noble 24.04, jammy 22.04), a component per level of the
# processor (v3: x86-64-v3, AVX2; v2: x86-64-v2). The versions before the new ones stay
# in the pool and in Packages, taken from the site as it is (an apt that read the index
# just before a publish still finds its files); older ones go.
#
# Environment: APT_SIGNING_KEY (OpenPGP, armoured, without a passphrase; made by aZ, the
# key 066D1CFEC0E3E3FA2CBA4B64261ACA1444125709 "aZ <github@azsupport.com>", since 25.11.2026
# 18:16: «подпись пусть будет не APT , а aZ рекламируя меня»), SITE_URL
# (the site as it is; default https://deb.azsupport.dev), FORCE=1 (a new site even when
# no package changed). GITHUB_OUTPUT: changed=yes|no.
# Exit status: 0 done, 1 failed (nothing to publish then).

set -u
site="${1:?usage: sh tools/build.sh <site directory>}"
live="${SITE_URL:-https://deb.azsupport.dev}"
src="https://github.com/azsupport/ports/releases/download"
fpr_want=066D1CFEC0E3E3FA2CBA4B64261ACA1444125709
suites="noble:24.04 jammy:22.04"
levels="v3 v2"
pkgs="az-ffmpeg az-imagemagick7"
w="$(mktemp -d "${RUNNER_TEMP:-/tmp}/apt.XXXXXX")" || exit 1
say() { printf '[apt %s] %s\n' "$(date -u '+%H:%M:%S')" "$*"; }
err() { echo "::error title=apt::$*"; exit 1; }
out() { [ -z "${GITHUB_OUTPUT:-}" ] || echo "$1" >> "$GITHUB_OUTPUT"; }
for t in apt-ftparchive gpg gpgv dpkg-deb curl sha256sum md5sum sha1sum xz gzip; do
    command -v "$t" > /dev/null 2>&1 || err "no $t"
done
mkdir -p "$site" || exit 1
[ -z "$(ls -A "$site")" ] || err "$site is not empty"
# absolute: the Release of each suite is made in its directory
site="$(cd "$site" && pwd)" || exit 1

# the key
export GNUPGHOME="$w/gnupg"
mkdir -m 700 "$GNUPGHOME" || exit 1
trap 'gpgconf --kill gpg-agent > /dev/null 2>&1' EXIT
[ -n "${APT_SIGNING_KEY:-}" ] || err "no secret APT_SIGNING_KEY"
printf '%s\n' "$APT_SIGNING_KEY" | gpg --batch --quiet --import 2> "$w/import.log" || err "the key does not import: $(tail -n 1 "$w/import.log")"
fpr="$(gpg --batch --with-colons --list-secret-keys | awk -F: '$1 == "fpr" { print $10; exit }')"
[ "$fpr" = "$fpr_want" ] || err "the key of APT_SIGNING_KEY is $fpr, not $fpr_want"
gpg --batch --export "$fpr" > "$site/azsupport.gpg" && gpg --batch --armor --export "$fpr" > "$site/azsupport.asc" || exit 1
# its user ID, for the log and index.html
uid="$(gpg --batch --with-colons --list-keys "$fpr" | awk -F: '$1 == "uid" { print $10; exit }')"
say "key $fpr $uid"
uid="$(printf '%s' "$uid" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')"

# entry <deb> <path in the site>: its stanza of Packages
entry() {
    dpkg-deb -f "$1" | sed '/^$/d'
    printf 'Filename: %s\nSize: %s\nMD5sum: %s\nSHA1: %s\nSHA256: %s\n\n' "$2" "$(stat -c %s "$1")" \
        "$(md5sum < "$1" | cut -d ' ' -f 1)" "$(sha1sum < "$1" | cut -d ' ' -f 1)" "$(sha256sum < "$1" | cut -d ' ' -f 1)"
}
# field <stanza file> <name>
field() { sed -n "s/^$2: //p" "$1" | head -n 1; }

new=""
old=""
for sv in $suites; do
    suite="${sv%%:*}"; ver="${sv#*:}"; rel="ubuntu${ver%%.*}"
    for lvl in $levels; do
        tag="az-$rel-amd64-$lvl"
        d="$site/dists/$suite/$lvl/binary-amd64"
        mkdir -p "$d" "$w/$suite-$lvl" || exit 1
        : > "$d/Packages"
        # the site as it is: its Packages of this suite and level (none the first time)
        curl -fsSL -o "$w/$suite-$lvl/Packages.live" "$live/dists/$suite/$lvl/binary-amd64/Packages" 2>/dev/null || : > "$w/$suite-$lvl/Packages.live"
        for p in $pkgs; do
            f="$w/$suite-$lvl/$p.deb"
            curl -fsSL --retry 3 -o "$f" "$src/$tag/$p-$rel-amd64-$lvl.deb" &&
                curl -fsSL --retry 3 -o "$f.sha256" "$src/$tag/$p-$rel-amd64-$lvl.deb.sha256" ||
                err "$tag: $p-$rel-amd64-$lvl.deb does not download"
            [ "$(cut -d ' ' -f 1 "$f.sha256")" = "$(sha256sum < "$f" | cut -d ' ' -f 1)" ] || err "$tag: $p does not match its .sha256"
            [ "$(dpkg-deb -f "$f" Package)" = "$p" ] && [ "$(dpkg-deb -f "$f" Architecture)" = amd64 ] || err "$tag: the file of $p is not $p for amd64"
            v="$(dpkg-deb -f "$f" Version)"
            case "$v" in *"~$rel."*) ;; *) err "$tag: $p $v is not a build for Ubuntu $ver" ;; esac
            path="pool/$lvl/a/$p/${p}_${v}_amd64.deb"
            mkdir -p "$site/pool/$lvl/a/$p" && cp "$f" "$site/$path" || exit 1
            entry "$site/$path" "$path" >> "$d/Packages"
            new="$new $suite/$lvl/$p=$v"
            # the version before (the highest of the site other than this one), kept
            awk -v p="$p" -v v="$v" 'BEGIN { RS = ""; FS = "\n" }
                { pk = ""; vv = ""; fn = ""; sh = ""
                  for (i = 1; i <= NF; i++) {
                      if ($i ~ /^Package: /) pk = substr($i, 10)
                      if ($i ~ /^Version: /) vv = substr($i, 10)
                      if ($i ~ /^Filename: /) fn = substr($i, 11)
                      if ($i ~ /^SHA256: /) sh = substr($i, 9) }
                  if (pk == p && vv != v) print vv "\t" fn "\t" sh }' "$w/$suite-$lvl/Packages.live" > "$w/$suite-$lvl/$p.prev"
            pv=""; pf=""; ps=""
            while IFS="$(printf '\t')" read -r cv cf cs; do
                if [ -z "$pv" ] || dpkg --compare-versions "$cv" gt "$pv"; then pv="$cv"; pf="$cf"; ps="$cs"; fi
            done < "$w/$suite-$lvl/$p.prev"
            # every version of the site, for changed below
            for lv in $(awk -v p="$p" 'BEGIN { RS = ""; FS = "\n" } { pk = ""; vv = ""
                for (i = 1; i <= NF; i++) { if ($i ~ /^Package: /) pk = substr($i, 10); if ($i ~ /^Version: /) vv = substr($i, 10) }
                if (pk == p) print vv }' "$w/$suite-$lvl/Packages.live"); do
                old="$old $suite/$lvl/$p=$lv"
            done
            if [ -n "$pv" ] && dpkg --compare-versions "$pv" lt "$v"; then
                mkdir -p "$site/${pf%/*}" &&
                    curl -fsSL --retry 3 -o "$site/$pf" "$live/$pf" &&
                    [ "$(sha256sum < "$site/$pf" | cut -d ' ' -f 1)" = "$ps" ] &&
                    entry "$site/$pf" "$pf" >> "$d/Packages" &&
                    say "$suite/$lvl: $p $pv kept next to $v" ||
                    echo "::warning title=apt::$suite/$lvl: $p $pv of the site not kept (it does not download or match)"
            fi
        done
        gzip -9nk "$d/Packages" && xz -9k "$d/Packages" || exit 1
        say "$suite/$lvl: $(grep -c '^Package: ' "$d/Packages") packages"
    done
    (
        cd "$site/dists/$suite" &&
            apt-ftparchive -o APT::FTPArchive::Release::Origin=azsupport -o APT::FTPArchive::Release::Label=azsupport \
                -o "APT::FTPArchive::Release::Suite=$suite" -o "APT::FTPArchive::Release::Codename=$suite" \
                -o "APT::FTPArchive::Release::Version=$ver" -o "APT::FTPArchive::Release::Components=$levels" \
                -o APT::FTPArchive::Release::Architectures=amd64 \
                -o "APT::FTPArchive::Release::Description=FFmpeg and ImageMagick 7 of azsupport for Ubuntu $ver (v3: x86-64-v3, v2: x86-64-v2)" \
                release . > "$w/Release-$suite" && mv "$w/Release-$suite" Release &&
            gpg --batch --yes --pinentry-mode loopback --passphrase '' --local-user "$fpr" --digest-algo SHA512 --clearsign -o InRelease Release &&
            gpg --batch --yes --pinentry-mode loopback --passphrase '' --local-user "$fpr" --digest-algo SHA512 -abs -o Release.gpg Release &&
            gpgv --quiet --keyring "$site/azsupport.gpg" InRelease 2> /dev/null &&
            gpgv --quiet --keyring "$site/azsupport.gpg" Release.gpg Release 2> /dev/null
    ) || err "dists/$suite: the Release is not made or not signed"
done

# apt reads each suite and level of the new site (file:) and takes the new versions
for sv in $suites; do
    suite="${sv%%:*}"
    for lvl in $levels; do
        q="$w/apt-$suite-$lvl"
        mkdir -p "$q/lists/partial" "$q/archives/partial" "$q/etc" || exit 1
        echo "deb [signed-by=$site/azsupport.gpg] file:$site $suite $lvl" > "$q/etc/sources.list"
        a() {
            sb=""; [ "$(id -u)" != 0 ] || sb="-o APT::Sandbox::User=root"
            # shellcheck disable=SC2086
            "$@" -q $sb -o Dir::State::Lists="$q/lists" -o Dir::Cache="$q" -o Dir::Cache::archives="$q/archives" \
                -o Dir::Etc::SourceList="$q/etc/sources.list" -o Dir::Etc::SourceParts=/nonexistent -o Debug::NoLocking=1
        }
        a apt-get update > "$q.log" 2>&1 && ! grep -q -E '^(E|W):' "$q.log" || err "$suite/$lvl: apt does not take the site: $(grep -E '^(E|W):' "$q.log" | head -n 2 | tr '\n' ' ')"
        for p in $pkgs; do
            want="$(printf '%s\n' $new | sed -n "s|^$suite/$lvl/$p=||p")"
            got="$(a apt-cache policy "$p" 2>/dev/null | sed -n 's/^ *Candidate: //p')"
            [ "$got" = "$want" ] || err "$suite/$lvl: apt takes $p ${got:-none}, not $want"
        done
    done
done
say "apt takes every suite and level (file:)"

cat > "$site/index.html" <<EOF
<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"><title>deb.azsupport.dev</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>body{font:16px/1.5 system-ui,sans-serif;max-width:52rem;margin:2rem auto;padding:0 1rem}pre{background:#f4f4f4;padding:1rem;overflow-x:auto}</style>
</head><body>
<h1>deb.azsupport.dev</h1>
<p>FFmpeg and ImageMagick 7 of azsupport for Ubuntu 24.04 (noble) and 22.04 (jammy), amd64:
<code>az-ffmpeg</code>, <code>az-imagemagick7</code> (into /usr/local). Built by
<a href="https://github.com/azsupport/ports">azsupport/ports</a> (tools/ubuntu), this repository by
<a href="https://github.com/azsupport/deb">azsupport/deb</a>.</p>
<p>The level of the processor: <code>/lib64/ld-linux-x86-64.so.2 --help | grep supported</code> &mdash;
x86-64-v3 (or v4): the component <code>v3</code>; x86-64-v2 only: <code>v2</code>.</p>
<pre>sudo install -d -m 0755 /etc/apt/keyrings
sudo curl -fsSL -o /etc/apt/keyrings/azsupport.gpg https://deb.azsupport.dev/azsupport.gpg
echo "deb [signed-by=/etc/apt/keyrings/azsupport.gpg] https://deb.azsupport.dev \$(. /etc/os-release &amp;&amp; echo \$VERSION_CODENAME) v3" | sudo tee /etc/apt/sources.list.d/azsupport.list
sudo apt-get update
sudo apt-get install -y az-ffmpeg az-imagemagick7</pre>
<p>The key: <code>$fpr</code> ($uid):
<code>gpg --show-keys /etc/apt/keyrings/azsupport.gpg</code>.</p>
<p>Built $(date -u '+%Y-%m-%d %H:%M UTC'):$(printf ' %s' $new | sed 's/ \([^ ]*\)/<br><code>\1<\/code>/g')</p>
</body></html>
EOF
: > "$site/.nojekyll"

# changed: a version built now that the site has not
miss=""
for x in $new; do
    case " $old " in *" $x "*) ;; *) miss="$miss $x" ;; esac
done
if [ -n "$miss" ] || [ -n "${FORCE:-}" ]; then
    out changed=yes
    say "changed:${miss:- (FORCE)}"
else
    out changed=no
    say "nothing changed: the site has$new"
fi
