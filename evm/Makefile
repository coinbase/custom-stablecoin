# Build the project
build:
	clear && forge clean && forge build

# Build only src
build-production:
	clear && forge clean && forge build --skip test --build-info src

# Update the committed gas snapshot baseline
snapshot:
	forge snapshot

# Check for gas regressions against the committed baseline
snapshot-diff:
	forge snapshot --diff