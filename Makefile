SHELL := /bin/bash
DEMO ?= 01-helloworld

.PHONY: setup build upload monitor smoke visual-smoke camera-ocr camera-aligner camera-diagnose official-demos official-build official-upload official-smoke official-build-all xiaozhi-latest xiaozhi-download xiaozhi-inspect xiaozhi-flash xiaozhi-source-clone xiaozhi-source-check cloud-ai-build cloud-ai-upload cloud-ai-smoke cloud-ai-relay audio-vad-build audio-vad-smoke speaker-output-build speaker-output-smoke sensor-status-build sensor-status-smoke touch-status-build touch-status-smoke interaction-dashboard-build interaction-dashboard-smoke install-hooks board-list clean

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

camera-diagnose:
	./scripts/camera-diagnose.sh

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

audio-vad-build:
	SKETCH=sketches/audio_vad_probe BUILD_PATH=.arduino-build/audio_vad_probe ./scripts/build.sh

audio-vad-smoke:
	./scripts/audio-vad-smoke.sh

speaker-output-build:
	SKETCH=sketches/speaker_output_probe BUILD_PATH=.arduino-build/speaker_output_probe ./scripts/build.sh

speaker-output-smoke:
	./scripts/speaker-output-smoke.sh

sensor-status-build:
	SKETCH=sketches/sensor_status_probe BUILD_PATH=.arduino-build/sensor_status_probe ./scripts/build.sh

sensor-status-smoke:
	./scripts/sensor-status-smoke.sh

touch-status-build:
	SKETCH=sketches/touch_status_probe BUILD_PATH=.arduino-build/touch_status_probe ./scripts/build.sh

touch-status-smoke:
	./scripts/touch-status-smoke.sh

interaction-dashboard-build:
	SKETCH=sketches/interaction_dashboard BUILD_PATH=.arduino-build/interaction_dashboard ./scripts/build.sh

interaction-dashboard-smoke:
	./scripts/interaction-dashboard-smoke.sh

install-hooks:
	git config core.hooksPath .githooks
	chmod +x .githooks/pre-push scripts/update-readme-for-feat-push.sh

board-list:
	arduino-cli board list
	arduino-cli board listall | rg -i 'waveshare|amoled|esp32.?s3|touch' || true

clean:
	rm -rf .arduino-build .logs
