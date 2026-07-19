# Run once after cloning: make setup
# To update the ryoku shell:
#     make update
#     make install

UPSTREAM := https://github.com/neur0map/ryoku-arch.git
UPSTREAM_BRANCH := main

.PHONY: setup status update regen-patches

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

install:
	ryoku/shell/deploy.sh
