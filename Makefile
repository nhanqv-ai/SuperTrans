# ==============================================================================
# SuperTrans Makefile
# Native macOS AI Personal Translator (Universal 2: arm64 + x86_64)
# Bundle ID: com.nhanqv.supertrans
# ==============================================================================

APP_NAME = SuperTrans
BUNDLE_ID = com.nhanqv.supertrans
BUNDLE_NAME = $(APP_NAME).app
BUNDLE_DIR = $(BUNDLE_NAME)/Contents
MACOS_DIR = $(BUNDLE_DIR)/MacOS
FRAMEWORKS_DIR = $(BUNDLE_DIR)/Frameworks
RESOURCES_DIR = $(BUNDLE_DIR)/Resources
BUILD_DIR = .build

ifneq ($(wildcard /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk),)
    SDK_PATH := /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk
else ifneq ($(wildcard /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk),)
    SDK_PATH := /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk
else
    SDK_PATH := $(shell xcrun --show-sdk-path)
endif
export SDKROOT := $(SDK_PATH)

SWIFTC = swiftc
SWIFT = swift
CODESIGN = codesign
INSTALL_NAME_TOOL = install_name_tool
LIPO = lipo

TARGET_ARM64 = arm64-apple-macos13.0
TARGET_X86_64 = x86_64-apple-macos13.0
HOST_ARCH = $(shell uname -m)
TARGET_HOST = $(HOST_ARCH)-apple-macos13.0
VERSION ?= $(shell /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Sources/SuperTrans/App/Info.plist 2>/dev/null || echo "1.0.0")
PACKAGE_ZIP = $(APP_NAME)-v$(VERSION).zip

CORE_SRCS = $(shell find Sources/SuperTransCore -name '*.swift' 2>/dev/null)
APP_SRCS  = $(shell find Sources/SuperTrans -name '*.swift' 2>/dev/null)

SWIFTC_FLAGS_COMMON = -sdk $(SDKROOT)
SWIFTC_FLAGS_DEBUG  = $(SWIFTC_FLAGS_COMMON) -g -Onone
SWIFTC_FLAGS_RELEASE= $(SWIFTC_FLAGS_COMMON) -O -whole-module-optimization

.PHONY: all build release icon app bundle package test clean help

all: build

help:
	@echo "SuperTrans Build System Targets:"
	@echo "  make build    - Compile Universal 2 debug dynamic library and executable"
	@echo "  make release  - Compile Universal 2 release dynamic library and executable"
	@echo "  make icon     - Generate AppIcon.icns and Assets/AppIcon.png"
	@echo "  make app      - Assemble and codesign standalone SuperTrans.app (Universal 2)"
	@echo "  make package  - Package distributable SuperTrans-v$(VERSION).zip"
	@echo "  make test     - Run automated test suite"
	@echo "  make clean    - Clean build artifacts"

build:
	@rm -rf $(BUILD_DIR)/modules/SuperTransCore.swiftmodule $(BUILD_DIR)/modules/SuperTrans.swiftmodule
	@mkdir -p $(BUILD_DIR)/modules/SuperTransCore.swiftmodule $(BUILD_DIR)/modules/SuperTrans.swiftmodule
	@mkdir -p $(BUILD_DIR)/lib/arm64 $(BUILD_DIR)/lib/x86_64 $(BUILD_DIR)/bin/arm64 $(BUILD_DIR)/bin/x86_64
	@echo "Compiling SuperTransCore slices (Debug: arm64 + x86_64)..."
	$(SWIFTC) $(SWIFTC_FLAGS_DEBUG) -target $(TARGET_ARM64) \
		-emit-library \
		-emit-module -emit-module-path $(BUILD_DIR)/modules/SuperTransCore.swiftmodule/arm64-apple-macos.swiftmodule \
		-module-name SuperTransCore \
		-parse-as-library \
		-Xlinker -install_name -Xlinker @rpath/libSuperTransCore.dylib \
		$(CORE_SRCS) \
		-o $(BUILD_DIR)/lib/arm64/libSuperTransCore.dylib
	$(SWIFTC) $(SWIFTC_FLAGS_DEBUG) -target $(TARGET_X86_64) \
		-emit-library \
		-emit-module -emit-module-path $(BUILD_DIR)/modules/SuperTransCore.swiftmodule/x86_64-apple-macos.swiftmodule \
		-module-name SuperTransCore \
		-parse-as-library \
		-Xlinker -install_name -Xlinker @rpath/libSuperTransCore.dylib \
		$(CORE_SRCS) \
		-o $(BUILD_DIR)/lib/x86_64/libSuperTransCore.dylib
	$(LIPO) -create -output $(BUILD_DIR)/lib/libSuperTransCore.dylib \
		$(BUILD_DIR)/lib/arm64/libSuperTransCore.dylib \
		$(BUILD_DIR)/lib/x86_64/libSuperTransCore.dylib
	@echo "Compiling SuperTrans executable slices (Debug: arm64 + x86_64)..."
	$(SWIFTC) $(SWIFTC_FLAGS_DEBUG) -target $(TARGET_ARM64) \
		-I $(BUILD_DIR)/modules \
		-L $(BUILD_DIR)/lib/arm64 \
		-lSuperTransCore \
		-Xlinker -rpath -Xlinker $(BUILD_DIR)/lib \
		-parse-as-library \
		$(APP_SRCS) \
		-o $(BUILD_DIR)/bin/arm64/$(APP_NAME)
	$(SWIFTC) $(SWIFTC_FLAGS_DEBUG) -target $(TARGET_X86_64) \
		-I $(BUILD_DIR)/modules \
		-L $(BUILD_DIR)/lib/x86_64 \
		-lSuperTransCore \
		-Xlinker -rpath -Xlinker $(BUILD_DIR)/lib \
		-parse-as-library \
		$(APP_SRCS) \
		-o $(BUILD_DIR)/bin/x86_64/$(APP_NAME)
	$(LIPO) -create -output $(BUILD_DIR)/bin/$(APP_NAME) \
		$(BUILD_DIR)/bin/arm64/$(APP_NAME) \
		$(BUILD_DIR)/bin/x86_64/$(APP_NAME)
	@echo "Debug Universal 2 build complete."

icon: $(BUILD_DIR)/Resources/AppIcon.icns

$(BUILD_DIR)/Resources/AppIcon.icns: Scripts/generate_icon.swift
	@mkdir -p $(BUILD_DIR)/Resources $(BUILD_DIR)/bin
	@echo "Generating SuperTrans AppIcon.icns..."
	$(SWIFTC) $(SWIFTC_FLAGS_COMMON) -target $(TARGET_HOST) Scripts/generate_icon.swift -o $(BUILD_DIR)/bin/generate_icon
	$(BUILD_DIR)/bin/generate_icon $@

app: icon
	@echo "Packaging $(BUNDLE_NAME) standalone Universal 2 application bundle..."
	@mkdir -p $(MACOS_DIR) $(FRAMEWORKS_DIR) $(RESOURCES_DIR)
	@rm -rf $(BUILD_DIR)/modules/SuperTransCore.swiftmodule $(BUILD_DIR)/modules/SuperTrans.swiftmodule
	@mkdir -p $(BUILD_DIR)/modules/SuperTransCore.swiftmodule $(BUILD_DIR)/modules/SuperTrans.swiftmodule
	@mkdir -p $(BUILD_DIR)/lib/arm64 $(BUILD_DIR)/lib/x86_64 $(BUILD_DIR)/bin/arm64 $(BUILD_DIR)/bin/x86_64
	@echo "Compiling SuperTransCore dynamic library slices (Release: arm64 + x86_64)..."
	$(SWIFTC) $(SWIFTC_FLAGS_RELEASE) -target $(TARGET_ARM64) \
		-emit-library \
		-emit-module -emit-module-path $(BUILD_DIR)/modules/SuperTransCore.swiftmodule/arm64-apple-macos.swiftmodule \
		-module-name SuperTransCore \
		-parse-as-library \
		-Xlinker -install_name -Xlinker @rpath/libSuperTransCore.dylib \
		$(CORE_SRCS) \
		-o $(BUILD_DIR)/lib/arm64/libSuperTransCore.dylib
	$(SWIFTC) $(SWIFTC_FLAGS_RELEASE) -target $(TARGET_X86_64) \
		-emit-library \
		-emit-module -emit-module-path $(BUILD_DIR)/modules/SuperTransCore.swiftmodule/x86_64-apple-macos.swiftmodule \
		-module-name SuperTransCore \
		-parse-as-library \
		-Xlinker -install_name -Xlinker @rpath/libSuperTransCore.dylib \
		$(CORE_SRCS) \
		-o $(BUILD_DIR)/lib/x86_64/libSuperTransCore.dylib
	$(LIPO) -create -output $(BUILD_DIR)/lib/libSuperTransCore.dylib \
		$(BUILD_DIR)/lib/arm64/libSuperTransCore.dylib \
		$(BUILD_DIR)/lib/x86_64/libSuperTransCore.dylib
	@echo "Compiling SuperTrans standalone executable slices (Release: arm64 + x86_64)..."
	$(SWIFTC) $(SWIFTC_FLAGS_RELEASE) -target $(TARGET_ARM64) \
		-I $(BUILD_DIR)/modules \
		-L $(BUILD_DIR)/lib/arm64 \
		-lSuperTransCore \
		-parse-as-library \
		-Xlinker -rpath -Xlinker @executable_path/../Frameworks \
		$(APP_SRCS) \
		-o $(BUILD_DIR)/bin/arm64/$(APP_NAME)
	$(SWIFTC) $(SWIFTC_FLAGS_RELEASE) -target $(TARGET_X86_64) \
		-I $(BUILD_DIR)/modules \
		-L $(BUILD_DIR)/lib/x86_64 \
		-lSuperTransCore \
		-parse-as-library \
		-Xlinker -rpath -Xlinker @executable_path/../Frameworks \
		$(APP_SRCS) \
		-o $(BUILD_DIR)/bin/x86_64/$(APP_NAME)
	$(LIPO) -create -output $(MACOS_DIR)/$(APP_NAME) \
		$(BUILD_DIR)/bin/arm64/$(APP_NAME) \
		$(BUILD_DIR)/bin/x86_64/$(APP_NAME)
	@chmod 755 $(MACOS_DIR)/$(APP_NAME)
	@cp -f $(BUILD_DIR)/lib/libSuperTransCore.dylib $(FRAMEWORKS_DIR)/libSuperTransCore.dylib
	@chmod 755 $(FRAMEWORKS_DIR)/libSuperTransCore.dylib
	$(INSTALL_NAME_TOOL) -id @rpath/libSuperTransCore.dylib $(FRAMEWORKS_DIR)/libSuperTransCore.dylib
	@cp -f Sources/SuperTrans/App/Info.plist $(BUNDLE_DIR)/Info.plist
	@chmod 644 $(BUNDLE_DIR)/Info.plist
	@printf "APPL????" > $(BUNDLE_DIR)/PkgInfo
	@chmod 644 $(BUNDLE_DIR)/PkgInfo
	@cp -f $(BUILD_DIR)/Resources/AppIcon.icns $(RESOURCES_DIR)/AppIcon.icns
	@chmod 644 $(RESOURCES_DIR)/AppIcon.icns
	@echo "Signing $(BUNDLE_NAME) with designated identifier $(BUNDLE_ID)..."
	$(CODESIGN) --force --sign - $(FRAMEWORKS_DIR)/libSuperTransCore.dylib
	$(CODESIGN) --force --sign - -r='designated => identifier "$(BUNDLE_ID)"' $(MACOS_DIR)/$(APP_NAME)
	$(CODESIGN) --force --sign - -r='designated => identifier "$(BUNDLE_ID)"' $(BUNDLE_NAME)
	$(CODESIGN) -v --deep --strict $(BUNDLE_NAME)
	@echo "$(BUNDLE_NAME) standalone Universal 2 bundle complete."

bundle: app

package: app
	@echo "Creating distributable Universal 2 archive: $(PACKAGE_ZIP)..."
	@rm -f $(PACKAGE_ZIP)
	@ditto -c -k --sequesterRsrc --keepParent $(BUNDLE_NAME) $(PACKAGE_ZIP)
	@echo "Created $(PACKAGE_ZIP)"

test: build
	@echo "Compiling and running SuperTrans verification test suite..."
	$(SWIFTC) $(SWIFTC_FLAGS_DEBUG) -target $(TARGET_HOST) \
		-I $(BUILD_DIR)/modules \
		-L $(BUILD_DIR)/lib/$(HOST_ARCH) \
		-lSuperTransCore \
		-Xlinker -rpath -Xlinker $(BUILD_DIR)/lib/$(HOST_ARCH) \
		-parse-as-library \
		Sources/SuperTrans/Presentation/CursorPopupFrameCalculator.swift \
		Sources/SuperTrans/Services/ShortcutNavigator.swift \
		Tests/SuperTransTests/SuperTransTests.swift \
		-o $(BUILD_DIR)/bin/test_runner
	$(BUILD_DIR)/bin/test_runner

clean:
	@rm -rf $(BUILD_DIR) $(BUNDLE_NAME) SuperTrans-*.zip
	@echo "Clean complete."
