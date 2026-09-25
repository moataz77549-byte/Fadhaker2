#!/usr/bin/env bash
set -euo pipefail
umask 077
mkdir -p /var/log/icecast2
chown nobody:nogroup /var/log/icecast2
runtime_dir="$(mktemp -d /tmp/tarteel-icecast.XXXXXX)"
config_path="$runtime_dir/icecast.xml"
trap 'rm -f "$config_path"; rmdir "$runtime_dir"' EXIT
node /opt/tarteel/render-config.mjs /opt/tarteel/icecast.xml.template "$config_path"
exec icecast2 -c "$config_path"
