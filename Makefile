# Run once after cloning: make setup
# To update the ryoku shell:
#     make update
#     make test
#     make install

UPSTREAM := https://github.com/neur0map/ryoku-arch.git
UPSTREAM_BRANCH := main

.PHONY: setup status update regen-patches test

setup:
	git remote add upstream $(UPSTREAM) || true
	git fetch upstream $(UPSTREAM_BRANCH)

update:
	git fetch upstream $(UPSTREAM_BRANCH)
	git rebase upstream/$(UPSTREAM_BRANCH)
	git am patches/*.patch

regen-patches:
	mkdir -p patches
	git format-patch upstream/$(UPSTREAM_BRANCH) -o patches/ --no-stat

# Pure-JS unit + lint tests behind the Quickshell surfaces (no display, no
# Quickshell dep). Run after `make update` so patches/*.patch are already
# applied and the tree under test is what `make install` would actually ship.
test:
	tests/shell-unit-tests.sh

install:
	ryoku/shell/deploy.sh
