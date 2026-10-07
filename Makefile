.PHONY: project open test build

# Generate ScreenshotBrain.xcodeproj from project.yml (needs `brew install xcodegen`).
project:
	xcodegen generate

open: project
	open ScreenshotBrain.xcodeproj

# Unit tests for every module, on an iPhone simulator.
test:
	cd Packages/SBKit && xcodebuild test -scheme SBKit-Package -destination "$$(../../scripts/sim-destination.sh)"

# Build the app for the simulator without signing.
build: project
	xcodebuild build -project ScreenshotBrain.xcodeproj -scheme ScreenshotBrain \
		-destination "$$(scripts/sim-destination.sh)" CODE_SIGNING_ALLOWED=NO
