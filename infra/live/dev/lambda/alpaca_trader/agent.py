"""Bedrock Converse tool-use loop with hard turn and cost caps."""

import logging

logger = logging.getLogger()
MAX_TOKENS_PER_TURN = 8000

# Prompt caching (2026-10-01, fixed 2026-10-02): every turn in this loop
# resends the full system prompt, the full tool spec list, and the full
# accumulated message history -- only the newest tool results are actually
# new each turn. A cache checkpoint tells Bedrock "everything up to here is
# a stable prefix you've already seen," so a repeat of that prefix on the
# next turn is read from cache instead of billed as fresh input.
#
# Bedrock enforces a hard maximum of 4 cache breakpoints per request (hit
# this directly: "A maximum of 4 blocks with cache_control may be provided.
# Found 5" on a real Converse call, once a run reached its third tool-call
# round). The first version of this code put a breakpoint on every new
# tool-result message and never removed the earlier ones, so the count grew
# without bound across a run's turns -- any run needing more than two tool
# rounds would have failed outright, which is most real runs (slot 1 alone
# typically needs 7-13 turns). Fixed here to a fixed 3-breakpoint budget
# that never grows: one on the system prompt, one on the tool list, and one
# "rolling" breakpoint in messages that moves to the newest message each
# turn instead of leaving a trail behind it. Verified against the real
# Bedrock API across a multi-tool-call run (cache reads appeared from the
# second turn onward, no validation error) before this went anywhere near
# live trading.
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
    rolling_cache_holder = messages[0]
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
        # Move the one rolling breakpoint here instead of adding another:
        # leaving the old one in place would keep growing past Bedrock's
        # 4-breakpoint cap as the conversation gets longer.
        rolling_cache_holder["content"].pop()
        results.append(_CACHE_POINT)
        new_message = {"role": "user", "content": results}
        messages.append(new_message)
        rolling_cache_holder = new_message
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
