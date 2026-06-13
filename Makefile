SHELL := /bin/bash
DEMO ?= 01-helloworld

.PHONY: setup build upload monitor smoke visual-smoke camera-ocr camera-aligner official-demos official-build official-upload official-smoke official-build-all xiaozhi-latest xiaozhi-download xiaozhi-inspect xiaozhi-flash xiaozhi-source-clone xiaozhi-source-check cloud-ai-build cloud-ai-upload cloud-ai-smoke cloud-ai-relay install-hooks board-list clean

setup:
	./scripts/setup.sh

build:
	./scripts/build.sh

upload:
	./scripts/upload.sh

monitor:
	./scripts/monitor.sh

smoke:
	./scripts/smoke.sh

visual-smoke:
	./scripts/visual-smoke.sh

camera-ocr:
	./scripts/camera-ocr.sh

camera-aligner:
	swift run CameraAligner

official-demos:
	./scripts/official-demo.sh list

official-build:
	./scripts/official-demo.sh build $(DEMO)

official-upload:
	./scripts/official-demo.sh upload $(DEMO)

official-smoke:
	./scripts/official-demo.sh smoke $(DEMO)

official-build-all:
	./scripts/official-demo.sh build-all

xiaozhi-latest:
	./scripts/xiaozhi.sh latest

xiaozhi-download:
	./scripts/xiaozhi.sh download

xiaozhi-inspect:
	./scripts/xiaozhi.sh inspect

xiaozhi-flash:
	./scripts/xiaozhi.sh flash $(CONFIRM)

xiaozhi-source-clone:
	./scripts/xiaozhi.sh source-clone

xiaozhi-source-check:
	./scripts/xiaozhi.sh source-check

cloud-ai-build:
	SKETCH=sketches/cloud_ai_terminal BUILD_PATH=.arduino-build/cloud_ai_terminal ./scripts/build.sh

cloud-ai-upload:
	SKETCH=sketches/cloud_ai_terminal BUILD_PATH=.arduino-build/cloud_ai_terminal ./scripts/upload.sh

cloud-ai-smoke:
	./scripts/cloud-ai-terminal-smoke.sh

cloud-ai-relay:
	python3 ./scripts/cloud-ai-relay.py --port $(ARDUINO_PORT)

install-hooks:
	git config core.hooksPath .githooks
	chmod +x .githooks/pre-push scripts/update-readme-for-feat-push.sh

board-list:
	arduino-cli board list
	arduino-cli board listall | rg -i 'waveshare|amoled|esp32.?s3|touch' || true

clean:
	rm -rf .arduino-build .logs
