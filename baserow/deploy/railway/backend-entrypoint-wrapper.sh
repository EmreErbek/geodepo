#!/bin/bash
# Railway volume mounts can be owned by root; Baserow runs as UID 9999.
set -euo pipefail

BASEROW_UID="${BASEROW_DOCKER_UID:-9999}"
BASEROW_GID="${BASEROW_DOCKER_GID:-9999}"

if [[ -d /baserow/media ]]; then
  chown -R "${BASEROW_UID}:${BASEROW_GID}" /baserow/media
  chmod -R u+rwX,g+rwX /baserow/media
fi

exec /usr/local/bin/su-exec "${BASEROW_UID}:${BASEROW_GID}" \
  /bin/bash /baserow/backend/docker/docker-entrypoint.sh "$@"