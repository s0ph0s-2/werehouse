# Configure here
VERSION := 0.1
REDBEAN_VERSION := 2.2
OUTPUT := hyperphantasia.com
SRV_DIR := srv
LIBS := lib/third_party/fullmoon.lua \
    lib/third_party/uuid.lua \
    lib/db.lua \
	lib/functools.lua \
	lib/scraper_pipeline.lua \
	lib/scrapers/bluesky.lua \
	lib/network_utils.lua \
	lib/web.lua
SRCS := src/.init.lua \
    src/templates/accept_invite.html \
    src/templates/login.html \
	src/templates/home.html
TEST_LIBS := lib/third_party/luaunit.lua

# Infrastructure variables here
ABOUT_FILE := $(SRV_DIR)/.lua/about.lua
REDBEAN := redbean-$(REDBEAN_VERSION).com
TEST_REDBEAN := test-$(REDBEAN)
SRCS_OUT := $(patsubst src/%,$(SRV_DIR)/%,$(SRCS))
LIBS_OUT := $(patsubst lib/%,$(SRV_DIR)/.lua/%,$(LIBS))
TEST_LIBS_OUT := $(patsubst lib/%,$(SRV_DIR)/.lua/%,$(TEST_LIBS))
$(info $(SRCS_OUT))
$(info $(LIBS_OUT))
$(info $(TEST_LIBS_OUT))

build: $(OUTPUT)

clean:
	rm -r $(SRV_DIR) $(TESTS_DIR)
	rm -f $(OUTPUT) $(TEST_REDBEAN)

test: $(TEST_REDBEAN)
	./$< -i test/test.lua

.PHONY: build clean test

# Don't delete any of these if make is interrupted
.PRECIOUS: $(SRV_DIR)/. $(SRV_DIR)%/.

# Create directories (and their child directories) automatically.
$(SRV_DIR)/.:
	mkdir -p $@

$(SRV_DIR)%/.:
	mkdir -p $@

$(ABOUT_FILE):
	echo "return { NAME = '$(OUTPUT)', VERSION = '$(VERSION)', REDBEAN_VERSION = '$(REDBEAN_VERSION)' }" > "$@"

$(REDBEAN):
	curl -sSL "https://redbean.dev/$(REDBEAN)" -o "$(REDBEAN)" && chmod +x $(REDBEAN)
	shasum -c redbean.sums

# Via https://ismail.badawi.io/blog/automatic-directory-creation-in-make/
# Expand prerequisite lists twice, with automatic variables (like $(@D)) in
# scope the second time.  This sets up the right dependencies for the automatic
# directory creation rules above. (The $$ is so that the first expansion
# replaces $$ with $ and makes the rule syntactically valid the second time.)
.SECONDEXPANSION:

$(SRV_DIR)/.lua/%.lua: lib/%.lua | $$(@D)/.
	cp $< $@

$(SRV_DIR)/%.html: src/%.html | $$(@D)/.
	cp $< $@

$(SRV_DIR)/.init.lua: src/.init.lua | $$(@D)/.
	cp $< $@

$(SRV_DIR)/%.css: src/%.css | $$(@D)/.
	cp $< $@

# Remove SRV_DIR from the start of each path, and also don't try to zip Redbean
# into itself.
$(OUTPUT): $(REDBEAN) $(SRCS_OUT) $(LIBS_OUT) $(ABOUT_FILE)
	if [ ! -f "$@" ]; then cp "$(REDBEAN)" "$@"; fi
	cd srv && zip -R "../$@" $(patsubst $(SRV_DIR)/%,%,$(filter-out $<,$?))

$(TEST_REDBEAN): $(REDBEAN) $(SRCS_OUT) $(LIBS_OUT) $(TEST_LIBS_OUT) $(ABOUT_FILE)
	if [ ! -f "$@" ]; then cp "$(REDBEAN)" "$@"; fi
	cd srv && zip -R "../$@" $(patsubst $(SRV_DIR)/%,%,$(filter-out $<,$?))
