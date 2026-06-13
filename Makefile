SHELL := /bin/bash

.PHONY: setup build upload monitor smoke visual-smoke camera-ocr board-list clean

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

board-list:
	arduino-cli board list
	arduino-cli board listall | rg -i 'waveshare|amoled|esp32.?s3|touch' || true

clean:
	rm -rf .arduino-build .logs
