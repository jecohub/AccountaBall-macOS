SWIFT    := swiftc
SDK      := /Library/Developer/CommandLineTools/SDKs/MacOSX14.5.sdk
TARGET   := arm64-apple-macosx14.0
BUILD    := .build/manual

LIB_SRCS  := $(shell find Sources/AccountaBall -name "*.swift" | sort)
TEST_SRCS  := $(shell find Tests/AccountaBallTests -name "*.swift" | sort) \
               Tests/MicroTest.swift
RUNNER    := Tests/TestRunner/main.swift
APP_SRCS  := Sources/AccountaBallApp/main.swift

SWIFT_FLAGS := -target $(TARGET) -sdk $(SDK)

.PHONY: test build run clean

# ── Library (all app logic) ────────────────────────────────────────────────────
$(BUILD)/AccountaBall.o: $(LIB_SRCS)
	@mkdir -p $(BUILD)
	$(SWIFT) $(SWIFT_FLAGS) \
	  -module-name AccountaBall \
	  -parse-as-library \
	  -whole-module-optimization \
	  -enable-testing \
	  -emit-module-path $(BUILD)/AccountaBall.swiftmodule \
	  -c -o $@ \
	  $(LIB_SRCS)

# ── Test runner ────────────────────────────────────────────────────────────────
$(BUILD)/run-tests: $(BUILD)/AccountaBall.o $(TEST_SRCS) $(RUNNER)
	$(SWIFT) $(SWIFT_FLAGS) \
	  $(BUILD)/AccountaBall.o \
	  $(TEST_SRCS) $(RUNNER) \
	  -I $(BUILD) \
	  -o $@

test: $(BUILD)/run-tests
	$(BUILD)/run-tests

# ── App binary ─────────────────────────────────────────────────────────────────
$(BUILD)/AccountaBallApp: $(LIB_SRCS) $(APP_SRCS)
	@mkdir -p $(BUILD)
	$(SWIFT) $(SWIFT_FLAGS) \
	  -whole-module-optimization \
	  $(LIB_SRCS) $(APP_SRCS) \
	  -o $@

build: $(BUILD)/AccountaBallApp

run: build
	$(BUILD)/AccountaBallApp

clean:
	rm -rf $(BUILD)
