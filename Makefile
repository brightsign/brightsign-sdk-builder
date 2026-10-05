# brightsign-sdk-builder -- provisions the shared build cache for a build box:
# the custom BrightSign cross-compile SDK, the RKNN toolkit clone, and the
# rknn_tk2 Docker image. Run once per build box; consumer repos (e.g.
# argus-rtsp-watcher) read the cache this fills.

BRIGHTSIGN_OS_VERSION ?= 9.1.52
RKNN_TAG ?= v2.3.0
export BRIGHTSIGN_OS_VERSION RKNN_TAG

# Shared cache location, resolved by the single source of truth (scripts/lib/cache.sh).
# Override with ARGUS_CACHE_DIR (default ../argus-build-cache, parallel to this repo).
# ARGUS_CACHE_DIR is forwarded explicitly so a command-line override reaches $(shell).
CACHE_SH := ARGUS_CACHE_DIR='$(ARGUS_CACHE_DIR)' bash scripts/lib/cache.sh print
CACHE_DIR := $(shell $(CACHE_SH) cache)
SDK_DIR := $(shell $(CACHE_SH) sdk)
SDK_ENV := $(shell $(CACHE_SH) sdk-env)
TOOLKIT_DIR := $(shell $(CACHE_SH) toolkit)
BSOE_DIR := $(shell $(CACHE_SH) bsoe)
export ARGUS_CACHE_DIR

.DEFAULT_GOAL := help

help:                ## Print available targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  %-12s %s\n", $$1, $$2}'

build: sdk toolkit   ## Provision everything into the shared cache (SDK + toolkit + rknn_tk2 image)

sdk:                 ## Build the custom cross-compile SDK from OS source into the cache (needs docker + ~25GB + network; hours)
	bash scripts/build-sdk.sh

toolkit:             ## Clone the RKNN toolkit into the cache and build the host-global rknn_tk2 image (needs docker + network)
	bash scripts/build-toolkit.sh

cache-info:          ## Show the resolved shared-cache location and what is present
	@echo "ARGUS_CACHE_DIR : $(if $(ARGUS_CACHE_DIR),$(ARGUS_CACHE_DIR) (override),(unset -> default))"
	@echo "cache   : $(CACHE_DIR)"
	@echo "sdk     : $(SDK_DIR)  [$(if $(wildcard $(SDK_ENV)),present,absent)]"
	@echo "toolkit : $(TOOLKIT_DIR)  [$(if $(wildcard $(TOOLKIT_DIR)),present,absent)]"
	@echo "bsoe    : $(BSOE_DIR)  [$(if $(wildcard $(BSOE_DIR)),present,absent)]"
	@docker image inspect bsoe-build >/dev/null 2>&1 && echo "docker  : bsoe-build image  [present]" || echo "docker  : bsoe-build image  [absent]"
	@docker image inspect rknn_tk2 >/dev/null 2>&1 && echo "docker  : rknn_tk2 image   [present]" || echo "docker  : rknn_tk2 image   [absent]"

run-tests:           ## Validate the provisioner (script syntax, recipe layer, cache resolver) -- no network/build
	@echo "==> bash -n on all scripts"
	@for f in scripts/*.sh scripts/lib/*.sh; do bash -n "$$f" && echo "  OK  $$f"; done
	@echo "==> recipe layer present"
	@test -f bsoe-recipes/meta-bs/conf/layer.conf || { echo "ERROR: bsoe-recipes/meta-bs layer missing" >&2; exit 1; }
	@echo "  OK  bsoe-recipes/meta-bs ($$(find bsoe-recipes -type f | wc -l | tr -d ' ') files)"
	@echo "==> cache resolver"
	@bash scripts/lib/cache.sh print cache >/dev/null && echo "  OK  scripts/lib/cache.sh"

test: run-tests      ## Alias for run-tests

clean:               ## Reclaim the large OE build tree from the cache (keeps the installed SDK + toolkit)
	rm -rf "$(BSOE_DIR)"
	@echo "Removed OE build tree: $(BSOE_DIR) (SDK + toolkit kept)"

cache-clean:         ## Remove the ENTIRE shared cache (SDK + toolkit + OE tree) -- AFFECTS ALL PROJECTS
	@echo "Removing the shared cache used by every project: $(CACHE_DIR)"
	rm -rf "$(CACHE_DIR)"
	@echo "Shared cache removed. Docker images are left; remove with: docker rmi rknn_tk2 bsoe-build"

.PHONY: help build sdk toolkit cache-info run-tests test clean cache-clean
