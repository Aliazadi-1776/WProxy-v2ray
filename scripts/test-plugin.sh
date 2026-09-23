#!/bin/sh
set -eu
cd "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
make
./validate-plugin ./libnm-vpn-plugin-wproxy.so
