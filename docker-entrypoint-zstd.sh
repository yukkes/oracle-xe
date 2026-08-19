#!/bin/sh
set -eu

archive="${ORACLE_BASE}/${ORACLE_SID}.tar.zst"

if [ -f "${archive}" ]; then
  echo "CONTAINER: uncompressing database data files with zstd-11, please wait..."
  extract_start="$(date '+%s')"
  LD_LIBRARY_PATH="${ORACLE_BASE}/compat-lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}" \
    /usr/local/bin/zstd -dc "${archive}" \
    | tar -xpf - -C "${ORACLE_BASE}/oradata"
  extract_end="$(date '+%s')"
  echo "CONTAINER: done uncompressing database data files, duration: $((extract_end - extract_start)) seconds."
  rm "${archive}"
fi

export LD_LIBRARY_PATH="${ORACLE_BASE}/compat-lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
exec /bin/bash /opt/oracle/container-entrypoint.sh "$@"
