.PHONY: build tilt-test tilt-deploy

all: build

.PHONY: build
build: sdk/node_modules
	cd ethereum && make build
	cd sdk && npm run build

sdk/node_modules:
	cd sdk && npm ci

.PHONY: tilt-test
tilt-test: tilt-deploy
	bash testing/run_tilt_tests.sh

.PHONY: tilt-deploy
tilt-deploy: build
	cd ethereum && bash shell-scripts/deploy_to_tilt.sh

## NOTE: run tilt-deploy before running this command,
## but if you ran tilt-test already, no need (since the 
## contracts are already deployed)
.PHONY: generate-vaa
generate-vaa: build
	cd sdk && npx ts-node src/__tmp__/generate-vaa.ts

.PHONY: clean
clean:
	cd ethereum && make clean
	cd sdk && npm run clean
