# P2 ESP-Claw / OpenClaw Agent Harness

The `esp_claw_agent` sketch is an Arduino compatibility harness for the ESP-Claw / OpenClaw direction. It does not replace the official ESP-Claw firmware. Instead, it gives this board repo a deterministic way to validate the agent control surfaces that ESP-Claw emphasizes: IM chat input, event-driven sensing, local rule execution, MCP-style tools, and local memory.

Reference context:

- ESP-Claw describes a local loop of sensing, reasoning, decision-making, and execution on Espressif chips: https://esp-claw.com/en/tutorial/
- The upstream project highlights IM chat, dynamic Lua loading, MCP server/client behavior, and local structured memory: https://github.com/espressif/esp-claw

## What It Proves

- The AMOLED can render an agent status surface with OCR-friendly `CLAW OK` text.
- The CST9217 touch controller initializes and can cycle agent pages.
- A host-side relay can drive the same conceptual loop that ESP-Claw uses: `CLAW_SENSE`, `CLAW_REASON`, `CLAW_DECIDE`, and `CLAW_ACT`.
- The serial protocol can validate MCP-style tool calls, IM chat commands, local rule additions, and memory writes without Wi-Fi credentials or audio devices.

## Commands

```bash
make esp-claw-agent-build
make esp-claw-agent-smoke
ESP_CLAW_AGENT_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 make esp-claw-agent-smoke
```

The smoke script uploads the harness, adds a deterministic rule, emits events, calls an MCP-style tool, sends one chat message, writes one memory item, and verifies that unmatched events fall back to an `LLM:REQUEST` action.

## Serial Protocol

- `PING` returns `PONG`.
- `CAPS?` emits `CLAW_CAPS`.
- `PAGE:HOME`, `PAGE:RULES`, `PAGE:MCP`, and `PAGE:MEMORY` switch pages.
- `RULE:ADD:<name>:<event>:<action>` adds a deterministic local rule.
- `EVENT:<event>:<value>` runs the sense/reason/decide/act loop.
- `MCP:CALL:<tool>:<arg>` records an MCP-style tool invocation and emits an action.
- `CHAT:<text>` simulates an IM chat command. Battery-related chat adds a display-dimming rule.
- `MEM:PUT:<tag>:<text>` records a tagged local memory item.
- `STATE?` emits `CLAW_STATE`.

## Acceptance Gates

- Compile: `make esp-claw-agent-build`
- Serial:
  - `CLAW_READY display=1 touch=1`
  - `CLAW_CAPS ... mcp=server,client ...`
  - `CLAW_RULE_ADDED name=desk_shake`
  - `CLAW_ACT source=rule action=TOOL:light.toggle`
  - `CLAW_MCP_CALL tool=display.message`
  - `CLAW_MEMORY_PUT tag=goal`
  - fallback `CLAW_ACT ... action=LLM:REQUEST`
- Visual: optional OCR sees `OK` on the AMOLED.

## Notes

- This is a control-plane harness, not the final ESP-Claw firmware image.
- Keep the deterministic serial rule/event path even after adding real ESP-Claw source builds. It gives the Skill a stable hardware smoke independent of IM credentials, cloud LLM keys, Wi-Fi, and camera positioning.
- This path is safe for late-night validation because it does not play audio or use the host microphone.

## Verified Locally

- `make hardware-smoke-suite HARDWARE_SMOKE_ARGS="--targets esp-claw-agent,tinyml-imu --per-target-timeout 420 --max-failures 1"`: built, uploaded, and passed `esp-claw-agent-smoke` on `/dev/cu.usbmodem83101`.
- Latest suite summary: `.logs/hardware-smoke-suite/20260614-044424/summary.json`.
- Latest target log: `.logs/hardware-smoke-suite/20260614-044424/esp-claw-agent.log`.
- Observed build size: `437991 bytes` program storage and `23872 bytes` dynamic memory.
- Observed summary: `esp_claw_agent_summary states=3 page_flow=RULES,MCP,MEMORY,HOME rules=4 events=3 actions=4 mcp=1 chats=1 memory=1 latest_action=LLM:REQUEST`.
