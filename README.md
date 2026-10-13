# brightsign-sdk-builder

Provisions a build box with the shared assets needed to cross-compile BrightSign
NPU applications: the **custom aarch64 cross-compile SDK**, the **RKNN model
toolkit**, and the **`rknn_tk2` Docker image**. Run it **once per build box**;
consumer repos (e.g. `argus-rtsp-watcher`) then build against the shared cache
this fills and never reproduce these heavy steps themselves.


## Why this exists

BrightSign publishes the **OS source** but no prebuilt SDK, and the SDK this
toolchain needs is a *custom* one: the `bsoe-recipes/` Yocto layer adds OpenCV,
the GStreamer RTSP plugins, the ext-bundle runtime and more into the SDK sysroot.
So the SDK must be **built from source**. That build is slow (~hours) and large
(~25 GB), and it is identical across every consumer project — exactly the kind of
work that belongs in one place, done once per machine.

## What it produces

Everything lands in a shared cache outside this repo (default
`../argus-build-cache`, override with `ARGUS_CACHE_DIR`):

| Asset | Location | Consumed by |
|-------|----------|-------------|
| Custom cross-compile SDK | `<cache>/sdk/` | engine/library/mosquitto cross-builds |
| RKNN toolkit clones | `<cache>/toolkit/` | model compilation |
| `rknn_tk2` Docker image | host Docker daemon (global) | model compilation |
| OS source + OE build tree | `<cache>/bsoe/` | (builder-internal; reclaim with `make clean`) |

## Prerequisites

- x86_64 Linux (Ubuntu/Debian recommended)
- Docker (or set `CONTAINER=podman`)
- ~25 GB free disk and a fast network for the first build
- `git`, `wget`, `rsync`

## Usage

```bash
make build        # provision everything into the shared cache (SDK + toolkit + image)
make cache-info   # show the resolved cache location and what is present
make clean        # reclaim the large OE build tree; keep the installed SDK + toolkit
```

Individual steps:

```bash
make sdk          # just the SDK
make toolkit      # just the RKNN toolkit clone + rknn_tk2 image
```

Every step is idempotent — an already-provisioned asset is detected and skipped,
so re-running `make build` is cheap once the box is set up.

### Targeting a different version

```bash
make build BRIGHTSIGN_OS_VERSION=9.1.53   # confirm it exists on BrightSign's S3 first
make build ARGUS_CACHE_DIR=/srv/argus-cache
```

## How consumers use it

Consumer repos resolve the same cache by the same convention (default
`../argus-build-cache`, or the shared `ARGUS_CACHE_DIR`). Once this provisioner
has run, a consumer's `make build` finds the SDK already installed and the toolkit
+ image already present, and proceeds straight to its own app build.

## Resetting

| Command | Effect |
|---------|--------|
| `make clean` | Removes the OE build tree from the cache (keeps SDK + toolkit) |
| `make cache-clean` | Removes the **entire** shared cache — affects every project |
| `docker rmi rknn_tk2 bsoe-build` | Removes the Docker images (shared, host-global) |

## Targets

Run `make` with no arguments to list all targets.

## Documentation

- [docs/DESIGN.md](docs/DESIGN.md) — architecture, the shared-cache contract, the
  SDK build sequence, the recipe layer, and the decision log.
