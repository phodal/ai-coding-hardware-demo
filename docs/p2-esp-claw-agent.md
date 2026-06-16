# P2 ESP-Claw / OpenClaw Agent Harness

The `esp_claw_agent` sketch is an Arduino compatibility harness for the ESP-Claw / OpenClaw direction. It does not replace the official ESP-Claw firmware. Instead, it gives this board repo a deterministic way to validate the agent control surfaces that ESP-Claw emphasizes: IM chat input, event-driven sensing, local rule execution, MCP-style tools, and local memory.

Reference context:

- ESP-Claw describes a local loop of sensing, reasoning, decision-making, and execution on Espressif chips: https://esp-claw.com/en/tutorial/
- The upstream project highlights IM chat, dynamic Lua loading, MCP server/client behavior, and local structured memory: https://github.com/espressif/esp-claw

## What It Proves

- The AMOLED can render an agent status surface with `AGENT` and `OK` markers.
- The CST9217 touch controller initializes and can cycle agent pages.
- A host-side relay can drive the same conceptual loop that ESP-Claw uses: `CLAW_SENSE`, `CLAW_REASON`, `CLAW_DECIDE`, and `CLAW_ACT`.
- The serial protocol can validate MCP-style tool registration/calls, IM chat commands, Lua-style rule loading, local rule execution, memory writes, and memory reads without Wi-Fi credentials or audio devices.

## Commands

```bash
make esp-claw-agent-build
make esp-claw-agent-smoke
ESP_CLAW_AGENT_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 DISPLAY_BRIGHTNESS=96 make esp-claw-agent-smoke
```

The smoke script uploads the harness, adds a deterministic rule, loads a Lua-style rule, emits events, registers and calls an MCP-style tool, sends one chat message, writes and reads one memory item, and verifies that unmatched events fall back to an `LLM:REQUEST` action.

When `ESP_CLAW_AGENT_VISUAL_SMOKE=1` is set, camera OCR checks the stable `OK` marker on the returned home page. Serial remains the authoritative proof for rules, MCP, IM chat, memory, and fallback actions.

## Serial Protocol

- `PING` returns `PONG`.
- `CAPS?` emits `CLAW_CAPS`.
- `PAGE:HOME`, `PAGE:RULES`, `PAGE:MCP`, and `PAGE:MEMORY` switch pages.
- `RULE:ADD:<name>:<event>:<action>` adds a deterministic local rule.
- `LUA:LOAD:<name>:<event>:<action>` loads a Lua-style rule and emits `CLAW_LUA_LOADED`.
- `EVENT:<event>:<value>` runs the sense/reason/decide/act loop.
- `MCP:REGISTER:<tool>:<schema>` registers an MCP-style tool.
- `MCP:CALL:<tool>:<arg>` records an MCP-style tool invocation and emits an action.
- `CHAT:<text>` simulates an IM chat command. Battery-related chat adds a display-dimming rule.
- `MEM:PUT:<tag>:<text>` records a tagged local memory item.
- `MEM:GET:<tag>` reads a tagged local memory item.
- `STATE?` emits `CLAW_STATE`.

## Acceptance Gates

- Compile: `make esp-claw-agent-build`
- Serial:
  - `CLAW_READY display=1 touch=1`
  - `CLAW_CAPS ... mcp=server,client ...`
  - `CLAW_RULE_ADDED name=desk_shake`
  - `CLAW_LUA_LOADED name=door_guard`
  - `CLAW_ACT source=rule action=TOOL:light.toggle`
  - `CLAW_MCP_REGISTER tool=display.message`
  - `CLAW_MCP_CALL tool=display.message`
  - `CLAW_MEMORY_PUT tag=goal`
  - `CLAW_MEMORY_GET tag=goal hit=1`
  - fallback `CLAW_ACT ... action=LLM:REQUEST`
- Visual: optional OCR sees `OK` on the AMOLED.

## Notes

- This is a control-plane harness, not the final ESP-Claw firmware image.
- Keep the deterministic serial rule/event path even after adding real ESP-Claw source builds. It gives the Skill a stable hardware smoke independent of IM credentials, cloud LLM keys, Wi-Fi, and camera positioning.
- This path is safe for late-night validation because it does not play audio or use the host microphone.

## Verified Locally

- `make esp-claw-agent-build`: passed with `439399 bytes` program storage and `24264 bytes` dynamic memory.
- `SKIP_BUILD=1 make esp-claw-agent-smoke`: uploaded to `/dev/cu.usbmodem83101` and validated Lua-style rule loading, MCP tool registration/call, IM chat rule creation, memory put/get, and `LLM:REQUEST` fallback.
- `make hardware-smoke-suite HARDWARE_SMOKE_ARGS="--target esp-claw-agent --skip-build --per-target-timeout 240 --max-failures 1"`: passed with summary `.logs/hardware-smoke-suite/20260614-055205/summary.json`.
- Observed summary: `esp_claw_agent_summary states=3 page_flow=RULES,MCP,MEMORY,HOME rules=5 events=4 actions=5 mcp=1 tools=1 chats=1 memory=1 lua=1 latest_action=LLM:REQUEST`.
- `ESP_CLAW_AGENT_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 DISPLAY_BRIGHTNESS=96 ESP_CLAW_AGENT_SECONDS=4 CAMERA_CAPTURE_TIMEOUT=8 make esp-claw-agent-smoke`: uploaded to `/dev/cu.usbmodem83101`, validated local rules, Lua loading, MCP register/call, IM chat, memory put/get, and `LLM:REQUEST` fallback, then camera OCR matched `OK`.
- Camera OCR artifacts: `.logs/camera-ocr-20260616-083338.jpg`, `.logs/camera-ocr-20260616-083338.processed.png`, `.logs/camera-ocr-20260616-083338.txt`.
- Latest visual build size: `439395 bytes` program storage and `24264 bytes` dynamic memory.
