"""Bedrock Converse tool-use loop with hard turn and cost caps."""

import logging

logger = logging.getLogger()
MAX_TOKENS_PER_TURN = 8000


def run_agent(bedrock, model_id, prices, system_text, user_text, toolbox, params):
    """Run the loop until the model stops or a cap is hit. Returns a summary."""
    in_price, out_price = prices
    messages = [{"role": "user", "content": [{"text": user_text}]}]
    cost = 0.0
    final_text = ""
    for turn in range(1, params.max_turns + 1):
        response = bedrock.converse(
            modelId=model_id,
            system=[{"text": system_text}],
            messages=messages,
            toolConfig={"tools": toolbox.specs()},
            inferenceConfig={"maxTokens": MAX_TOKENS_PER_TURN},
        )
        usage = response.get("usage", {})
        cost += usage.get("inputTokens", 0) * in_price
        cost += usage.get("outputTokens", 0) * out_price
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
