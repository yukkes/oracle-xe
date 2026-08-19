# syntax=docker/dockerfile:1.7

ARG FASTSTART_IMAGE=ghcr.io/gvenzl/oracle-xe:18-slim-faststart@sha256:ee0d7b8ac3665fb80219cbcb5a080cc202cc970120e1fbef592d7592274cef22

# Use the initialized Oracle home and database files from gvenzl only as build
# inputs. The expanded database files are never copied into the final image.
FROM ${FASTSTART_IMAGE} AS faststart

FROM faststart AS oracle-files

USER root
SHELL ["/bin/bash", "-c"]

# CI runs a single XE instance; installer, RAC, SDK, and GUI/admin trees are
# outside the tested runtime path. Remove them before the final COPY so their
# bytes do not remain in a lower image layer. The shared-library removals are
# covered by the Orafit Oracle 18c differential suite.
RUN mkdir -p /export/opt/oracle /export/etc \
    && cp -a /opt/oracle/{product,admin,audit,cfgtoollogs,checkpoints,diag,oraInventory,.bash_profile,container-entrypoint.sh,createAppUser,healthcheck.sh,resetPassword} /export/opt/oracle/ \
    && rm -rf /export/opt/oracle/product/18c/dbhomeXE/{addnode,clone,css,diagnostics,dv,mgw,oss,owm,racg,relnotes,sdk,slax,srvm,sqlj,usm,wwg} \
    && rm -f /export/opt/oracle/product/18c/dbhomeXE/lib/libcrs18.so \
    && rm -f /export/opt/oracle/product/18c/dbhomeXE/lib/libshpk*.so \
    && cp -a /etc/{oraInst.loc,oratab} /export/etc/

FROM debian:bookworm-slim AS archive

RUN apt-get update \
    && apt-get install -y --no-install-recommends tar zstd \
    && rm -rf /var/lib/apt/lists/*

COPY --from=faststart /opt/oracle/oradata/XE /tmp/oradata/XE

RUN tar --numeric-owner --create --file=- --directory=/tmp/oradata XE \
    | zstd -11 -T0 -o /tmp/XE.tar.zst - \
    && zstd -t /tmp/XE.tar.zst

RUN cp --dereference /usr/lib/x86_64-linux-gnu/libz.so.1 /tmp/libz.so.1 \
    && cp --dereference /usr/lib/x86_64-linux-gnu/liblz4.so.1 /tmp/liblz4.so.1 \
    && cp --dereference /usr/lib/x86_64-linux-gnu/liblzma.so.5 /tmp/liblzma.so.5 \
    && cp --dereference /usr/lib/x86_64-linux-gnu/libzstd.so.1 /tmp/libzstd.so.1

# BusyBox supplies the base userspace. Copy only Oracle's runtime files,
# required compatibility libraries, and the compressed database seed.
FROM busybox:glibc AS runtime

ENV ORACLE_BASE=/opt/oracle \
    ORACLE_BASE_CONFIG=/opt/oracle/product/18c/dbhomeXE \
    ORACLE_BASE_HOME=/opt/oracle/product/18c/dbhomeXE \
    ORACLE_HOME=/opt/oracle/product/18c/dbhomeXE \
    ORACLE_SID=XE \
    NLS_LANG=.AL32UTF8 \
    LD_LIBRARY_PATH=/opt/oracle/compat-lib \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/opt/oracle/product/18c/dbhomeXE/bin:/opt/oracle

COPY --from=faststart /bin/bash /bin/bash

COPY --from=faststart /lib64/libaio.so.1.0.1 /opt/oracle/compat-lib/libaio.so.1.0.1
COPY --from=faststart /lib64/libgcc_s-8-20210514.so.1 /opt/oracle/compat-lib/libgcc_s-8-20210514.so.1
COPY --from=faststart /lib64/libgfortran.so.3.0.0 /opt/oracle/compat-lib/libgfortran.so.3.0.0
COPY --from=faststart /lib64/libnsl-2.28.so /opt/oracle/compat-lib/libnsl-2.28.so
COPY --from=faststart /lib64/libquadmath.so.0.0.0 /opt/oracle/compat-lib/libquadmath.so.0.0.0
COPY --from=faststart /lib64/libtinfo.so.6.1 /opt/oracle/compat-lib/libtinfo.so.6.1

COPY --from=archive /usr/bin/zstd /usr/local/bin/zstd
COPY --from=archive --chown=54321:54321 /tmp/XE.tar.zst /opt/oracle/XE.tar.zst
COPY --from=archive /tmp/libz.so.1 /opt/oracle/compat-lib/libz.so.1
COPY --from=archive /tmp/liblz4.so.1 /opt/oracle/compat-lib/liblz4.so.1
COPY --from=archive /tmp/liblzma.so.5 /opt/oracle/compat-lib/liblzma.so.5
COPY --from=archive /tmp/libzstd.so.1 /opt/oracle/compat-lib/libzstd.so.1

COPY --from=oracle-files /export/opt/oracle /opt/oracle
COPY --from=oracle-files /export/etc/oraInst.loc /etc/oraInst.loc
COPY --from=oracle-files /export/etc/oratab /etc/oratab

COPY docker-entrypoint-zstd.sh /usr/local/bin/docker-entrypoint-zstd.sh

RUN ln -s libaio.so.1.0.1 /opt/oracle/compat-lib/libaio.so.1 \
    && ln -s /lib/libc.so.6 /opt/oracle/compat-lib/libdl.so.2 \
    && ln -s libgcc_s-8-20210514.so.1 /opt/oracle/compat-lib/libgcc_s.so.1 \
    && ln -s libgfortran.so.3.0.0 /opt/oracle/compat-lib/libgfortran.so.3 \
    && ln -s libnsl-2.28.so /opt/oracle/compat-lib/libnsl.so.1 \
    && ln -s libquadmath.so.0.0.0 /opt/oracle/compat-lib/libquadmath.so.0 \
    && ln -s /lib/libc.so.6 /opt/oracle/compat-lib/librt.so.1 \
    && ln -s libtinfo.so.6.1 /opt/oracle/compat-lib/libtinfo.so.6 \
    && addgroup -g 54321 oinstall \
    && addgroup -g 54322 dba \
    && adduser -D -u 54321 -G oinstall -h /opt/oracle -s /bin/bash oracle \
    && addgroup oracle dba \
    && mkdir -p /opt/oracle/oradata /container-entrypoint-initdb.d /container-entrypoint-startdb.d \
    && chown -R 54321:54321 /opt/oracle/oradata /container-entrypoint-initdb.d /container-entrypoint-startdb.d \
    && mkdir -p /var/tmp/.oracle \
    && chmod 1777 /var/tmp/.oracle \
    && chmod 755 /usr/local/bin/docker-entrypoint-zstd.sh \
    && chmod 755 /opt/oracle/container-entrypoint.sh /opt/oracle/healthcheck.sh /opt/oracle/createAppUser /opt/oracle/resetPassword

LABEL org.opencontainers.image.title="Oracle Database XE 18c on BusyBox with pruned Oracle Home and zstd-11 database data" \
      org.opencontainers.image.source="https://github.com/yukkes/oracle-xe"

USER oracle
WORKDIR /opt/oracle

HEALTHCHECK CMD /opt/oracle/healthcheck.sh >/dev/null || exit 1

ENTRYPOINT ["/usr/local/bin/docker-entrypoint-zstd.sh"]
