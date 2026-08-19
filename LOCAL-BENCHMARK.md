# Local validation of Oracle XE CI startup improvements

Test date: August 19, 2026

## Conclusion

Oracle Home pruning candidate D has been implemented. Compared with the
current image, the Oracle Home decreased from approximately 1,022.9 MB to
866.3 MB, the image decreased from approximately 1.60 GB to 1.44 GB, and the
median local time to reach `healthy` decreased from 26.8 seconds to 24.6
seconds.

Candidate D completed all 279 Oracle differential cases from Orafit on a
bridge network with zero failures. A fresh run against the local candidate D
image on August 19, 2026 produced 279 tests, zero failures, and zero errors.
The unpruned local baseline image produced the same result. `oradata` on
tmpfs remains a low-risk additional improvement.

`pzstd 1.5.7` had no benefit on its own and did not outperform tmpfs alone
when combined with tmpfs.

Storing the database files directly in an OCI layer reduced local startup by
approximately 11 seconds for a cached image. However, the image grew from
approximately 1.60 GB to 3.81 GB. Pull time on GitHub Actions could reverse
that result, so this option is not adopted without a cold-pull measurement on
Actions.

Oracle Home pruning was evaluated with file-access observation and the Orafit
differential suite. Unobserved files are not automatically considered unused;
the removals remain limited to candidate D and its tested single-instance XE
scope.

## Measurement environment and conditions

- WSL2, Podman 5.7.0, AMD64
- Host: 8 vCPUs, approximately 7.8 GiB of memory
- Three runs for each pattern
- Images were cached locally; pull time was excluded
- `--shm-size=1g`
- `ORACLE_PASSWORD=OrafitOracle18`
- `APP_USER=ORAFIT18`
- Healthcheck interval: 1 second; timeout: 5 seconds
- Measurements run from container start until Oracle reported `healthy`
- `archive_s` is the database archive extraction time from the container log

Podman did not support `--tmpfs ...:uid=54321,gid=54321`, so the tmpfs
measurements used `mode=0777`. On GitHub Actions Docker, specifying the Oracle
user's UID and GID should be preferred.

## Startup time comparison

| Pattern | Run 1 | Run 2 | Run 3 | Median | Archive median |
| --- | ---: | ---: | ---: | ---: | ---: |
| Current zstd-1.5.4 | 26.8 s | 25.9 s | 27.2 s | **26.8 s** | 15 s |
| Current + `oradata` tmpfs | 23.2 s | 19.6 s | 19.6 s | **19.6 s** | 8 s |
| `pzstd` 1.5.7 | 25.6 s | 26.9 s | 28.0 s | **26.9 s** | 16 s |
| `pzstd` 1.5.7 + tmpfs | 18.5 s | 19.6 s | 19.7 s | **19.6 s** | 9 s |
| Database files stored directly in an OCI layer | 16.0 s | 16.1 s | 13.7 s | **16.0 s** | - |
| Oracle Home pruning candidate D | 24.6 s | 23.2 s | 24.7 s | **24.6 s** | 15–16 s |

### Image size

| Pattern | Expanded local image size | Database seed |
| --- | ---: | ---: |
| Current zstd-1.5.4 | 1,603,653,020 bytes | `XE.tar.zst` 529,062,362 bytes |
| `pzstd` 1.5.7 | 1,608,237,552 bytes | `XE.tar.zst` 531,374,846 bytes |
| OCI layer storage | 3,812,920,215 bytes | Expanded `oradata/XE`, approximately 2.6 GiB |
| Oracle Home pruning candidate D | 1,440,226,783 bytes | `XE.tar.zst` 529,062,362 bytes |

The `pzstd 1.5.7` archive was approximately 2.3 MB larger than the current
archive, and its startup median did not improve. The tmpfs combination had the
same median as tmpfs alone.

## Decision by option

### A. Use tmpfs for `oradata` — candidate for adoption

In the local measurements, the median time to reach `healthy` decreased from
26.8 seconds to 19.6 seconds. Archive extraction also decreased from 15
seconds to 8 seconds.

This requires no image rebuild and is appropriate for temporary CI data. The
following option is worth testing in GitHub Actions:

```sh
docker run -d \
  --tmpfs /opt/oracle/oradata:rw,uid=54321,gid=54321 \
  ... \
  ghcr.io/yukkes/oracle-xe:18c-busybox
```

If UID/GID options are not portable, `mode=0777` can be used for disposable CI
containers.

### B. `pzstd 1.5.7` — rejected

zstd 1.5.7 was built from source, and its contrib `pzstd` was used for
compression and extraction. It did not show a faster extraction trend than
the current zstd, and the archive was larger.

The maintenance and build complexity of adding `pzstd` is not justified by
these results.

### C. Store database files directly in an OCI layer — conditional

Removing the explicit `XE.tar.zst` and startup extraction reduced the local
median time to reach `healthy` to 16.0 seconds. The expanded local image was
approximately 2.21 GB larger.

This measurement used a cached image. Pull time may dominate on GitHub-hosted
runners, so adoption requires comparing pull-start to `healthy` on Actions
after publishing the image.

### D. Prune Oracle Home — implemented and revalidated

Before copying the Oracle Home into the final image, candidate D removes
trees and shared libraries outside the tested single-instance XE runtime:

```text
product/18c/dbhomeXE/{addnode,clone,css,diagnostics,dv,mgw,oss,owm,
  racg,relnotes,sdk,slax,srvm,sqlj,usm,wwg}
product/18c/dbhomeXE/lib/libcrs18.so
product/18c/dbhomeXE/lib/libshpk*.so
```

The candidate was reconsidered against the large files called out during the
earlier observation pass:

| File or pattern | Size | Decision and evidence |
| --- | ---: | --- |
| `lib/libcrs18.so` | 76,052,521 bytes | Keep removed. The file is associated with cluster/RAC support; the single XE Orafit workload does not load it. The fresh 279-case differential passed. |
| `lib/libshpkavx218.so` | 12,131,248 bytes | Keep removed; covered by the same fresh differential run. |
| `lib/libshpkavx51218.so` | 11,693,428 bytes | Keep removed; covered by the same fresh differential run. |
| `lib/libshpksse4218.so` | 11,449,530 bytes | Keep removed; covered by the same fresh differential run. |
| `lib/libshpkavx18.so` | 11,340,530 bytes | Keep removed; covered by the same fresh differential run. |
| `sdk/proc` | 10,847,196 bytes | Keep removed with `sdk/`; it is outside the JDBC runtime. |
| `sdk/procob` | 10,495,520 bytes | Keep removed with `sdk/`; it is outside the JDBC runtime. |

The file-access and differential observations were:

- Full Oracle Home file count: 5,777
- Candidate D file count: 5,323
- Files observed during startup and SQL access: 58–59
- inotify events during all 279 candidate D cases: 22,029
- inotify overflow: 0
- SQL connection and `all_objects` query: successful
- `OracleDifferentialIT`: 279 tests, zero failures, zero errors

The fresh verification used both the candidate D image and the local
unpruned baseline image. Both reported Oracle Database 18c XE and passed all
279 cases. This supports the removals for the covered single-instance JDBC
workload; it does not establish compatibility for RAC/Clusterware,
precompiler, or other Oracle features outside that workload. No additional
unobserved files were removed based on size alone.

### E. Pre-create `APP_USER` — low priority

Credentials were not baked into the seed. The potential saving is small, while
including a fixed password in the image and regenerating the seed would add
complexity. It is therefore lower priority than tmpfs or OCI-layer testing.

## Test constraints

With rootless Podman and host networking, the Oracle container's healthcheck
could succeed while a host-side JDBC client still could not reach the
`XEPDB1` service. The verification therefore placed Oracle, PostgreSQL, and
Maven on the same bridge network and used container names for JDBC URLs.

On that bridge network, the Oracle SQL setup, PostgreSQL's `oracle_compat`
extension, and all 279 `OracleDifferentialIT` cases succeeded. A cold pull
measurement for the published image remains outstanding before applying this
to GitHub Actions.

## Recommended next changes

First build candidate D as the Oracle image and measure pull-start to
`healthy` across approximately five runs in the Orafit Oracle job. Combining
candidate D with tmpfs is expected to be faster than candidate D alone.
Do not adopt the `pzstd` or direct OCI-layer changes based on the current local
measurements.

The candidate D Dockerfile changes remain in this repository. Candidate A–C
verification images were local-only tags and were not published.
