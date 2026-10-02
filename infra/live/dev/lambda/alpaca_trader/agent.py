"""Bedrock Converse tool-use loop with hard turn and cost caps."""

import logging

logger = logging.getLogger()
MAX_TOKENS_PER_TURN = 8000

# Prompt caching (2026-10-01): every turn in this loop resends the full
# system prompt, the full tool spec list, and the full accumulated message
# history — only the newest tool results are actually new each turn. A
# cache checkpoint tells Bedrock "everything up to here is a stable prefix
# you've already seen," so a repeat of that prefix on the next turn is read
# from cache instead of billed as fresh input. Checkpoints go on the system
# block, the tool list, and the end of each message we send — the three
# places content either never changes (system, tools) or only grows by
# appending (messages).
#
# Anthropic's standard cache pricing (same on the direct API and Bedrock):
# a cache read is ~10% of the normal input price, a cache write carries a
# ~25% premium over it. Applied here so the cost cap stays meaningful
# instead of silently overcounting now-cheaper cached tokens as full price.
CACHE_READ_MULTIPLIER = 0.1
CACHE_WRITE_MULTIPLIER = 1.25
_CACHE_POINT = {"cachePoint": {"type": "default"}}


def run_agent(bedrock, model_id, prices, system_text, user_text, toolbox, params):
    """Run the loop until the model stops or a cap is hit. Returns a summary."""
    in_price, out_price = prices
    messages = [{"role": "user", "content": [{"text": user_text}, _CACHE_POINT]}]
    tools = toolbox.specs() + [_CACHE_POINT]
    cost = 0.0
    final_text = ""
    for turn in range(1, params.max_turns + 1):
        response = bedrock.converse(
            modelId=model_id,
            system=[{"text": system_text}, _CACHE_POINT],
            messages=messages,
            toolConfig={"tools": tools},
            inferenceConfig={"maxTokens": MAX_TOKENS_PER_TURN},
        )
        usage = response.get("usage", {})
        cost += usage.get("inputTokens", 0) * in_price
        cost += usage.get("outputTokens", 0) * out_price
        cache_read = usage.get("cacheReadInputTokens", 0)
        cache_write = usage.get("cacheWriteInputTokens", 0)
        cost += cache_read * in_price * CACHE_READ_MULTIPLIER
        cost += cache_write * in_price * CACHE_WRITE_MULTIPLIER
        message = response["output"]["message"]
        messages.append(message)
        texts = [b["text"] for b in message["content"] if "text" in b]
        final_text = "\n".join(texts) or final_text
        if response.get("stopReason") != "tool_use":
            return _summary("finished", turn, cost, final_text)
        results = []
        for block in message["content"]:
            if "toolUse" in block:
                use = block["toolUse"]
                output = toolbox.call(use["name"], use.get("input") or {})
                results.append(
                    {
                        "toolResult": {
                            "toolUseId": use["toolUseId"],
                            "content": [{"text": output}],
                        }
                    }
                )
        results.append(_CACHE_POINT)
        messages.append({"role": "user", "content": results})
        if cost > params.max_run_cost_usd:
            return _summary("cost_cap", turn, cost, final_text)
    return _summary("turn_cap", params.max_turns, cost, final_text)


def _summary(reason, turns, cost, final_text):
    return {
        "stopped": reason,
        "turns": turns,
        "cost_usd": round(cost, 4),
        "final_text": final_text[:2000],
    }
