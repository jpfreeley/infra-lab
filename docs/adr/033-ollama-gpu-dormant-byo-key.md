# ADR-033: Ollama GPU Server Dormant — Bring Your Own Claude Key

## Status

Accepted (supersedes initial Ollama-as-primary design)

## Context

A shared Ollama GPU server (g4dn.xlarge, T4 16GB) was deployed to provide
free local LLM inference (qwen2.5-coder:14b) for developer desktops. After
extensive testing, the local model proved inadequate for IDE-integrated AI:

1. **Tool calling broken**: qwen2.5-coder:14b via Ollama's OpenAI-compatible
   endpoint does not reliably execute structured function calls. Both Hermes
   Agent and Continue Agent mode produce JSON text instead of invoking tools.
2. **Unacceptable latency**: 64K context on a 14B Q4 model saturates the T4's
   16GB VRAM. Response time ~60-90 seconds per turn.
3. **Cost inefficiency**: g4dn.xlarge on-demand is $0.526/hr. Even with
   10-minute idle auto-stop, the GPU cost exceeds a reasonable Claude API
   budget for equivalent usage.
4. **Spot unreliable**: Spot instances hit `capacity-not-available` in
   us-east-1a, breaking the auto-start-on-desktop-launch guarantee.

## Decision

- **Disable Ollama auto-start**: Lambda no longer starts the Ollama instance
  when a desktop is provisioned.
- **Remove Ollama from desktop config**: No OLLAMA_HOST env vars, no Continue
  Ollama config, no Hermes setup.
- **Bring Your Own Key**: Continue extension pre-installed with Anthropic
  Claude as the default provider. Developers add their own API key.
- **Keep Terraform code**: `ollama.tf` remains in the codebase for future
  use. The infrastructure can be re-enabled if a better model/GPU combination
  becomes viable.

## Consequences

- Developers need an Anthropic API key for AI features (chat, autocomplete,
  agent, MCP). ~$5-20/month for typical usage.
- Full agent mode works (terminal commands, file edits, autonomous coding)
- MCP tool integration works
- No GPU infrastructure cost when Ollama is stopped
- Ollama can be manually started for experimentation:
  `aws ec2 start-instances --instance-ids <id>`
- Future: if qwen3 or similar models improve tool calling reliability, or
  if a larger GPU (A10G/A100) is justified, Ollama can be re-enabled by
  restoring the Lambda auto-start and desktop config.

## Lessons Learned

- Local LLMs on consumer-grade GPUs (T4 16GB) are viable for autocomplete
  but not for agentic workflows requiring tool calling
- Ollama's /v1 (OpenAI-compatible) endpoint does not guarantee structured
  tool_calls responses — models may emit JSON as text instead
- IMDSv2 is mandatory on AL2023 — all metadata calls need token headers
- Cron's PATH does not include /usr/local/bin — use full paths in cron scripts
- g4dn instances take 3-5 minutes to terminate (GPU detach)
- Spot with persistent stop behavior breaks auto-start guarantees
