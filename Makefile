.PHONY: gen zip open ios serve

BUNDLE_ID := com.ymzuiku.Ouchie
IOS_DIR   := ios
APP_PATH  := $(IOS_DIR)/build/Build/Products/Debug-iphoneos/Ouchie.app

serve:
	cd server && go run . ../client

zip:
	mkdir -p $(IOS_DIR)/Ouchie/Resources
	rm -f $(IOS_DIR)/Ouchie/Resources/client.zip
	cd client && zip -r --symlinks "$(CURDIR)/$(IOS_DIR)/Ouchie/Resources/client.zip" . -x "*.DS_Store"
	@echo "Built client.zip"

gen: zip
	cd $(IOS_DIR) && xcodegen generate

open: gen
	open $(IOS_DIR)/Ouchie.xcodeproj

ios: zip
	cd $(IOS_DIR) && xcodegen generate
	xcodebuild build \
		-project $(IOS_DIR)/Ouchie.xcodeproj \
		-scheme Ouchie \
		-configuration Debug \
		-arch arm64 \
		-sdk iphoneos \
		-derivedDataPath $(IOS_DIR)/build \
		-allowProvisioningUpdates \
		-quiet
	xcrun devicectl device install app --device DEVICE_UDID_REMOVED $(APP_PATH)
	xcrun devicectl device process launch --device DEVICE_UDID_REMOVED $(BUNDLE_ID)
