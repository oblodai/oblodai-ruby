# Every gate of this SDK, run locally (there is no hosted CI to lean on).
#
#   make ci                                   # drift + rubocop + specs + conformance + gem
#   OBLODAI_BACKEND=/path/to/oblodai-backend make ci
#
# The backend checkout (OBLODAI_BACKEND, else ../oblodai-backend) provides tools/sdkgen for the
# drift check and tools/sdkgen/conformance for the shared scenarios. Ruby runs on the host when it
# has `bundle`, else in docker (image RUBY_IMAGE, labelled oblodai.sdkcheck=1); gems go to
# vendor/bundle inside the repository either way.

BACKEND ?= $(if $(OBLODAI_BACKEND),$(OBLODAI_BACKEND),$(abspath $(CURDIR)/../oblodai-backend))
RUBY_IMAGE ?= ruby:3.3
GOTOOLCHAIN ?= go1.26.6
export GOTOOLCHAIN

BACKEND_MOUNT := $(if $(wildcard $(BACKEND)/tools/sdkgen),-v $(BACKEND):$(BACKEND):ro -e OBLODAI_BACKEND=$(BACKEND))
ifeq ($(shell command -v bundle 2>/dev/null),)
RUBY := docker run --rm --label oblodai.sdkcheck=1 --memory 2g -v $(CURDIR):/src -w /src $(BACKEND_MOUNT) \
	-e BUNDLE_PATH=vendor/bundle $(RUBY_IMAGE) bash -c
else
RUBY := OBLODAI_BACKEND=$(BACKEND) BUNDLE_PATH=vendor/bundle bash -c
endif

.PHONY: ci drift ruby-ci test lint regenerate

ci: drift ruby-ci ## every gate
	@echo "all gates green"

drift: ## fail when lib/oblodai/generated is not what tools/sdkgen makes of openapi.json
	OBLODAI_BACKEND=$(BACKEND) ./script/check_generated.sh --require

ruby-ci: ## rubocop, unit + contract + conformance specs, gem build
	$(RUBY) 'bundle install --quiet && bundle exec rake ci'

test:
	$(RUBY) 'bundle install --quiet && bundle exec rake spec'

lint:
	$(RUBY) 'bundle install --quiet && bundle exec rubocop'

regenerate: ## rewrite lib/oblodai/generated from the backend's openapi.json
	cd $(BACKEND)/tools/sdkgen && go run ./cmd/sdkgen -spec ../../services/core/api/openapi.json \
		-lang ruby -out $(CURDIR) -lock $(CURDIR)/names.lock
