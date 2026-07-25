#!/bin/sh
# Installs camtrack for the current Linux machine: picks .deb or .rpm based on the available
# package manager, downloads it from GitHub Releases, and installs it.
#
#   curl -sfL https://raw.githubusercontent.com/timphandev/camtrack-app/main/install.sh | sudo sh
#
# By default installs the latest stable release (a tag with no semver pre-release suffix, e.g.
# app@0.5.0). Flags:
#
#   --pre              also consider pre-release versions (e.g. app@0.6.0-beta.1) when picking latest
#   --version X.Y.Z    install this exact version instead of latest (accepts the pre-release
#                       suffix form too, e.g. --version 0.6.0-beta.1)
#   --force            allow installing a version older than (or equal to, if undetectable) the
#                       one currently installed
set -eu

REPO="timphandev/camtrack-app"

want_pre=0
want_version=""
force=0

while [ $# -gt 0 ]; do
    case "$1" in
        --pre)
            want_pre=1
            shift
            ;;
        --version)
            [ $# -ge 2 ] || { echo "--version requires an argument" >&2; exit 1; }
            want_version="$2"
            shift 2
            ;;
        --force)
            force=1
            shift
            ;;
        *)
            echo "unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

version_re='^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$'
if [ -n "$want_version" ]; then
    case "$want_version" in
        app@*) want_version=${want_version#app@} ;;
    esac
    if ! echo "$want_version" | grep -qE "$version_re"; then
        echo "invalid --version: $want_version (expected X.Y.Z or X.Y.Z-suffix)" >&2
        exit 1
    fi
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "install.sh must be run as root (e.g. via sudo)" >&2
    exit 1
fi

arch=$(uname -m)
case "$arch" in
    x86_64|amd64) arch=amd64 ;;
    aarch64|arm64) arch=arm64 ;;
    *)
        echo "unsupported architecture: $arch" >&2
        exit 1
        ;;
esac

if command -v apt >/dev/null 2>&1; then
    pkg=deb
elif command -v dnf >/dev/null 2>&1 || command -v yum >/dev/null 2>&1; then
    pkg=rpm
else
    echo "no supported package manager found (need apt, dnf, or yum)" >&2
    exit 1
fi

# semver_is_pre RAWVERSION — true (exit 0) if RAWVERSION (no leading "v") has a "-suffix" part.
semver_is_pre() {
    case "$1" in
        *-*) return 0 ;;
        *) return 1 ;;
    esac
}

# semver_core RAWVERSION — prints the "X.Y.Z" part, dropping any "-suffix".
semver_core() {
    echo "${1%%-*}"
}

# semver_gt A B — true (exit 0) if version A is strictly greater than version B. Compares the
# X.Y.Z core numerically first; if equal, a version with no pre-release suffix outranks one with
# a suffix (release > pre-release), otherwise the suffix is compared as a plain string — good
# enough for the -beta.N/-rc.N schemes this project actually uses, not a full semver-precedence
# implementation.
semver_gt() {
    a=$1
    b=$2
    a_core=$(semver_core "$a")
    b_core=$(semver_core "$b")

    if [ "$a_core" != "$b_core" ]; then
        higher=$(printf '%s\n%s\n' "$a_core" "$b_core" | sort -V | tail -n1)
        [ "$higher" = "$a_core" ]
        return $?
    fi

    a_is_pre=0; semver_is_pre "$a" && a_is_pre=1
    b_is_pre=0; semver_is_pre "$b" && b_is_pre=1

    if [ "$a_is_pre" -eq 0 ] && [ "$b_is_pre" -eq 1 ]; then
        return 0
    elif [ "$a_is_pre" -eq 1 ] && [ "$b_is_pre" -eq 0 ]; then
        return 1
    elif [ "$a_is_pre" -eq 1 ] && [ "$b_is_pre" -eq 1 ]; then
        a_suffix=${a#*-}
        b_suffix=${b#*-}
        [ "$a_suffix" != "$b_suffix" ] || return 1
        higher=$(printf '%s\n%s\n' "$a_suffix" "$b_suffix" | sort -V | tail -n1)
        [ "$higher" = "$a_suffix" ]
        return $?
    fi
    return 1
}

# Detect the currently-installed version, if any. Three distinct states matter below:
#   - camtrack not installed at all      -> already_installed=0, safe to skip the downgrade check
#   - installed but version undetectable -> already_installed=1, current_version="" (warn, don't block)
#   - installed with a known version     -> already_installed=1, current_version="X.Y.Z..."
already_installed=0
current_version=""
if command -v camtrack >/dev/null 2>&1; then
    already_installed=1
    current_version=$(camtrack --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?' | head -n1 || true)
    if [ -z "$current_version" ]; then
        echo "warning: camtrack is installed but its version could not be determined; skipping downgrade check" >&2
    fi
fi

if [ -n "$want_version" ]; then
    target_version="$want_version"
    tag="app@${target_version}"
    release_url="https://api.github.com/repos/${REPO}/releases/tags/${tag}"
    release_json=$(curl -sfL "$release_url") || {
        echo "release ${tag} not found in ${REPO}" >&2
        exit 1
    }
else
    all_tags=$(curl -sfL "https://api.github.com/repos/${REPO}/releases" \
        | grep '"tag_name"' \
        | cut -d'"' -f4)

    if [ -z "$all_tags" ]; then
        echo "no releases found in ${REPO}" >&2
        exit 1
    fi

    target_version=""
    for tag in $all_tags; do
        case "$tag" in
            app@*) v=${tag#app@} ;;
            *) continue ;;
        esac
        if [ "$want_pre" -eq 0 ] && semver_is_pre "$v"; then
            continue
        fi
        if [ -z "$target_version" ] || semver_gt "$v" "$target_version"; then
            target_version="$v"
        fi
    done

    if [ -z "$target_version" ]; then
        echo "no matching release found in ${REPO} (try --pre to include pre-releases)" >&2
        exit 1
    fi

    tag="app@${target_version}"
    release_url="https://api.github.com/repos/${REPO}/releases/tags/${tag}"
    release_json=$(curl -sfL "$release_url")
fi

if [ "$already_installed" -eq 1 ] && [ "$force" -eq 0 ]; then
    if [ -n "$current_version" ]; then
        if [ "$current_version" != "$target_version" ] && ! semver_gt "$target_version" "$current_version"; then
            echo "refusing to downgrade: installed version is ${current_version}, target is ${target_version}" >&2
            echo "pass --force to install this version anyway" >&2
            exit 1
        fi
    else
        echo "refusing to install ${target_version} over an unknown existing version without --force" >&2
        exit 1
    fi
fi

asset_pattern="linux-${arch}\\.${pkg}\"\$"
download_url=$(echo "$release_json" \
    | grep '"browser_download_url"' \
    | grep -E "$asset_pattern" \
    | head -n1 \
    | cut -d'"' -f4)

if [ -z "$download_url" ]; then
    echo "could not find a .${pkg} release asset for linux-${arch} in ${tag}" >&2
    exit 1
fi

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT
chmod 755 "$tmp_dir"
tmp_file="${tmp_dir}/camtrack.${pkg}"

echo "==> downloading camtrack ${target_version} (${pkg}, ${arch})"
curl -sfL -o "$tmp_file" "$download_url"

echo "==> installing package"
if [ "$pkg" = "deb" ]; then
    apt-get install -y "$tmp_file" >/dev/null
else
    if command -v dnf >/dev/null 2>&1; then
        dnf install -y "$tmp_file" >/dev/null
    else
        yum install -y "$tmp_file" >/dev/null
    fi
fi

service_state=$(systemctl is-active camtrack 2>/dev/null || true)

echo
echo "============================================================"
if [ -n "$current_version" ] && [ "$current_version" != "$target_version" ]; then
    echo " camtrack updated: ${current_version} -> ${target_version}"
else
    echo " camtrack ${target_version} installed"
fi
echo "============================================================"
echo " service status : ${service_state:-unknown}"
echo " check status    : systemctl status camtrack"
echo " follow logs      : journalctl -u camtrack -f"
echo "============================================================"
echo
