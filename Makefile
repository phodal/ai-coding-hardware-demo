SHELL := /bin/bash
DEMO ?= 01-helloworld

.PHONY: setup build upload monitor smoke visual-smoke camera-ocr camera-aligner official-demos official-build official-upload official-smoke official-build-all board-list clean

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

board-list:
	arduino-cli board list
	arduino-cli board listall | rg -i 'waveshare|amoled|esp32.?s3|touch' || true

clean:
	rm -rf .arduino-build .logs
