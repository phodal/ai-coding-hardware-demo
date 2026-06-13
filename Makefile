SHELL := /bin/bash
DEMO ?= 01-helloworld

.PHONY: setup build upload monitor smoke visual-smoke camera-ocr camera-aligner camera-diagnose feature-matrix-check feature-matrix-doc official-demos official-build official-upload official-smoke official-build-all xiaozhi-latest xiaozhi-download xiaozhi-inspect xiaozhi-flash xiaozhi-source-clone xiaozhi-source-check cloud-ai-build cloud-ai-upload cloud-ai-smoke cloud-ai-pipeline-smoke cloud-ai-cache-smoke cloud-ai-relay audio-vad-build audio-vad-smoke speaker-output-build speaker-output-smoke sensor-status-build sensor-status-smoke power-lifecycle-build power-lifecycle-smoke wifi-connectivity-build wifi-connectivity-smoke touch-status-build touch-status-smoke interaction-dashboard-build interaction-dashboard-smoke imu-interaction-build imu-interaction-smoke desk-widget-build desk-widget-smoke desk-widget-relay-smoke iot-panel-build iot-panel-smoke tinyml-imu-build tinyml-imu-smoke esp-claw-agent-build esp-claw-agent-smoke offline-voice-build offline-voice-smoke lvgl-visual-agent-build lvgl-visual-agent-smoke install-hooks board-list clean

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

feature-matrix-check:
	python3 ./scripts/feature-matrix-check.py

feature-matrix-doc:
	python3 ./scripts/feature-matrix-check.py --markdown > docs/hardware-verification-matrix.md

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

cloud-ai-pipeline-smoke:
	CLOUD_AI_PIPELINE=1 CLOUD_AI_EXPECT_SERIAL=PIPELINE_DONE ./scripts/cloud-ai-terminal-smoke.sh

cloud-ai-cache-smoke:
	CLOUD_AI_CACHE=1 CLOUD_AI_PIPELINE=1 CLOUD_AI_EXPECT_SERIAL=PIPELINE_DONE ./scripts/cloud-ai-terminal-smoke.sh

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

power-lifecycle-build:
	SKETCH=sketches/power_lifecycle_probe BUILD_PATH=.arduino-build/power_lifecycle_probe ./scripts/build.sh

power-lifecycle-smoke:
	./scripts/power-lifecycle-smoke.sh

wifi-connectivity-build:
	SKETCH=sketches/wifi_connectivity_probe BUILD_PATH=.arduino-build/wifi_connectivity_probe ./scripts/build.sh

wifi-connectivity-smoke:
	./scripts/wifi-connectivity-smoke.sh

touch-status-build:
	SKETCH=sketches/touch_status_probe BUILD_PATH=.arduino-build/touch_status_probe ./scripts/build.sh

touch-status-smoke:
	./scripts/touch-status-smoke.sh

interaction-dashboard-build:
	SKETCH=sketches/interaction_dashboard BUILD_PATH=.arduino-build/interaction_dashboard ./scripts/build.sh

interaction-dashboard-smoke:
	./scripts/interaction-dashboard-smoke.sh

imu-interaction-build:
	SKETCH=sketches/imu_interaction_probe BUILD_PATH=.arduino-build/imu_interaction_probe ./scripts/build.sh

imu-interaction-smoke:
	./scripts/imu-interaction-smoke.sh

desk-widget-build:
	SKETCH=sketches/desk_widget BUILD_PATH=.arduino-build/desk_widget ./scripts/build.sh

desk-widget-smoke:
	./scripts/desk-widget-smoke.sh

desk-widget-relay-smoke:
	./scripts/desk-widget-relay-smoke.sh

iot-panel-build:
	SKETCH=sketches/iot_control_panel BUILD_PATH=.arduino-build/iot_control_panel ./scripts/build.sh

iot-panel-smoke:
	./scripts/iot-panel-smoke.sh

tinyml-imu-build:
	SKETCH=sketches/tinyml_imu_classifier BUILD_PATH=.arduino-build/tinyml_imu_classifier ./scripts/build.sh

tinyml-imu-smoke:
	./scripts/tinyml-imu-smoke.sh

esp-claw-agent-build:
	SKETCH=sketches/esp_claw_agent BUILD_PATH=.arduino-build/esp_claw_agent ./scripts/build.sh

esp-claw-agent-smoke:
	./scripts/esp-claw-agent-smoke.sh

offline-voice-build:
	SKETCH=sketches/offline_voice_control BUILD_PATH=.arduino-build/offline_voice_control ./scripts/build.sh

offline-voice-smoke:
	./scripts/offline-voice-smoke.sh

lvgl-visual-agent-build:
	SKETCH=sketches/lvgl_visual_agent BUILD_PATH=.arduino-build/lvgl_visual_agent ./scripts/build.sh

lvgl-visual-agent-smoke:
	./scripts/lvgl-visual-agent-smoke.sh

install-hooks:
	git config core.hooksPath .githooks
	chmod +x .githooks/pre-push scripts/update-readme-for-feat-push.sh

board-list:
	arduino-cli board list
	arduino-cli board listall | rg -i 'waveshare|amoled|esp32.?s3|touch' || true

clean:
	rm -rf .arduino-build .logs
