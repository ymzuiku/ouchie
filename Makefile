.PHONY: gen zip open ios serve testflight

BUNDLE_ID := com.ymzuiku.ouchie
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

API_KEYS_DIR       := ../vibe-remote-api-keys
ASC_API_KEY_ID     := 523PH2J3BK
ASC_API_ISSUER_ID  := cdc01ff3-bd77-4719-b95d-1bb10b9c14ac
ASC_KEY_FULL_PATH  := $(shell cd $(API_KEYS_DIR) 2>/dev/null && pwd)/connect_AuthKey_$(ASC_API_KEY_ID).p8

testflight: zip
	@echo "=== TestFlight Release ==="
	cd $(IOS_DIR) && xcodegen generate
	@echo "Archiving..."
	cd $(IOS_DIR) && xcodebuild clean archive \
		-project Ouchie.xcodeproj \
		-scheme Ouchie \
		-archivePath build/Ouchie.xcarchive \
		-destination 'generic/platform=iOS' \
		-allowProvisioningUpdates \
		-authenticationKeyPath "$(ASC_KEY_FULL_PATH)" \
		-authenticationKeyID "$(ASC_API_KEY_ID)" \
		-authenticationKeyIssuerID "$(ASC_API_ISSUER_ID)"
	@echo "Uploading to App Store Connect..."
	cd $(IOS_DIR) && xcodebuild -exportArchive \
		-project Ouchie.xcodeproj \
		-archivePath build/Ouchie.xcarchive \
		-exportOptionsPlist ExportOptions.plist \
		-exportPath build/export \
		-allowProvisioningUpdates \
		-authenticationKeyPath "$(ASC_KEY_FULL_PATH)" \
		-authenticationKeyID "$(ASC_API_KEY_ID)" \
		-authenticationKeyIssuerID "$(ASC_API_ISSUER_ID)"
	@echo "=== Done! Check App Store Connect for the new build. ==="

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
	xcrun devicectl device install app --device $(OUCHIE_DEVICE_UDID) $(APP_PATH)
	xcrun devicectl device process launch --device $(OUCHIE_DEVICE_UDID) $(BUNDLE_ID)
