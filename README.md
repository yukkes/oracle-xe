# Oracle Database 18c XE on BusyBox

This repository builds an amd64-only Oracle Database 18c Express Edition image
for short-lived CI environments. The runtime image uses `busybox:glibc`; the
Oracle home and initialized database are taken from the pinned
[`gvenzl/oracle-xe` faststart image](https://github.com/gvenzl/oci-oracle-xe)
during the build.

The expanded database files are converted to a zstd-11 tar archive at build
time. The final image contains the archive and restores it on the first
container start. The expanded database files are not stored in the final image.

## Image

The package is published by GitHub Actions as:

```text
ghcr.io/yukkes/oracle-xe:18c-busybox
```

Set the package visibility to **Public** in the
[GHCR package settings](https://github.com/users/yukkes/packages/container/oracle-xe/settings).
After that, it can be used from another project without GHCR credentials:

```yaml
permissions:
  contents: read

services:
  oracle:
    image: ghcr.io/yukkes/oracle-xe:18c-busybox
    env:
      ORACLE_PASSWORD: TestPassword123
    ports:
      - 1521:1521
```

The database service is `XEPDB1`. The image healthcheck uses the upstream
Oracle XE healthcheck script.

## Local build

Podman or Docker with BuildKit is required:

```sh
podman build --format docker -t oracle-xe:local .
podman run --rm -p 1521:1521 \
  -e ORACLE_PASSWORD=TestPassword123 \
  oracle-xe:local
```

The build downloads no Oracle installer into this repository. Review and
comply with the Oracle Database XE license and the terms of the pinned
upstream image before distributing the resulting image. Oracle and Oracle
Database are trademarks of Oracle Corporation; this project is unofficial.
