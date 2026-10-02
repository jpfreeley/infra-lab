"""Tests for the Bedrock tool-use loop's cost accounting and cache points."""

import copy
import json

from conftest import TEST_LIMITS

import agent
import guardrails


class FakeToolbox:
    """A toolbox that answers one tool call, then stops."""

    def specs(self):
        return [{"toolSpec": {"name": "noop", "description": "", "inputSchema": {}}}]

    def call(self, name, args):
        return json.dumps({"ok": True})


class FakeBedrock:
    """Scripted Converse responses, one per call, with given usage.

    Snapshots messages as a deep copy: the caller keeps mutating the same
    list object across turns, so a stored reference would silently reflect
    later appends instead of what was actually sent on this call.
    """

    def __init__(self, responses):
        """Queue up the scripted responses to return in order."""
        self.responses = list(responses)
        self.requests = []

    def converse(self, **kwargs):
        snapshot = {**kwargs, "messages": copy.deepcopy(kwargs["messages"])}
        self.requests.append(snapshot)
        return self.responses.pop(0)


def tool_use_response(usage):
    return {
        "output": {
            "message": {
                "role": "assistant",
                "content": [
                    {"text": "working"},
                    {"toolUse": {"toolUseId": "t1", "name": "noop", "input": {}}},
                ],
            }
        },
        "stopReason": "tool_use",
        "usage": usage,
    }


def end_turn_response(usage):
    return {
        "output": {"message": {"role": "assistant", "content": [{"text": "done"}]}},
        "stopReason": "end_turn",
        "usage": usage,
    }


def params(**overrides):
    return guardrails.Params.from_dict({**TEST_LIMITS, **overrides})


def test_cache_points_placed_on_system_tools_and_every_message():
    bedrock = FakeBedrock([end_turn_response({"inputTokens": 100, "outputTokens": 10})])
    agent.run_agent(bedrock, "m", (1e-6, 1e-6), "sys", "hello", FakeToolbox(), params())
    request = bedrock.requests[0]
    assert request["system"][-1] == agent._CACHE_POINT
    assert request["toolConfig"]["tools"][-1] == agent._CACHE_POINT
    assert request["messages"][0]["content"][-1] == agent._CACHE_POINT


def _count_cache_points(request):
    count = sum(1 for b in request["system"] if b == agent._CACHE_POINT)
    count += sum(1 for t in request["toolConfig"]["tools"] if t == agent._CACHE_POINT)
    for message in request["messages"]:
        count += sum(1 for b in message["content"] if b == agent._CACHE_POINT)
    return count


def test_cache_point_moves_to_the_newest_message_not_accumulates():
    bedrock = FakeBedrock(
        [
            tool_use_response({"inputTokens": 100, "outputTokens": 10}),
            end_turn_response({"inputTokens": 50, "outputTokens": 5}),
        ]
    )
    agent.run_agent(bedrock, "m", (1e-6, 1e-6), "sys", "hello", FakeToolbox(), params())
    second_request = bedrock.requests[1]
    tool_result_message = second_request["messages"][-1]
    assert tool_result_message["content"][-1] == agent._CACHE_POINT
    # The initial user message must have given its breakpoint up, not kept it.
    assert agent._CACHE_POINT not in second_request["messages"][0]["content"]


def test_cache_breakpoints_never_exceed_bedrocks_hard_limit_of_four():
    """Bedrock rejects a request with more than 4 cache_control blocks.

    The first version of this code put a new breakpoint on every tool
    result and never removed old ones, so a long-running conversation
    would eventually violate this and fail outright.
    """
    responses = [tool_use_response({"inputTokens": 10, "outputTokens": 1})] * 8
    responses.append(end_turn_response({"inputTokens": 10, "outputTokens": 1}))
    bedrock = FakeBedrock(responses)
    agent.run_agent(
        bedrock, "m", (1e-6, 1e-6), "sys", "hello", FakeToolbox(), params(max_turns=20)
    )
    for request in bedrock.requests:
        assert _count_cache_points(request) <= 4


def test_cost_counts_fresh_tokens_at_full_price():
    bedrock = FakeBedrock(
        [end_turn_response({"inputTokens": 1000, "outputTokens": 100})]
    )
    result = agent.run_agent(
        bedrock, "m", (0.000004, 0.00002), "sys", "hello", FakeToolbox(), params()
    )
    assert result["cost_usd"] == round(1000 * 0.000004 + 100 * 0.00002, 4)


def test_cost_counts_cache_read_at_a_tenth_of_input_price():
    usage = {
        "inputTokens": 0,
        "outputTokens": 0,
        "cacheReadInputTokens": 1000,
        "cacheWriteInputTokens": 0,
    }
    bedrock = FakeBedrock([end_turn_response(usage)])
    result = agent.run_agent(
        bedrock, "m", (0.000004, 0.00002), "sys", "hello", FakeToolbox(), params()
    )
    assert result["cost_usd"] == round(1000 * 0.000004 * agent.CACHE_READ_MULTIPLIER, 4)


def test_cost_counts_cache_write_at_a_premium_over_input_price():
    usage = {
        "inputTokens": 0,
        "outputTokens": 0,
        "cacheReadInputTokens": 0,
        "cacheWriteInputTokens": 1000,
    }
    bedrock = FakeBedrock([end_turn_response(usage)])
    result = agent.run_agent(
        bedrock, "m", (0.000004, 0.00002), "sys", "hello", FakeToolbox(), params()
    )
    assert result["cost_usd"] == round(
        1000 * 0.000004 * agent.CACHE_WRITE_MULTIPLIER, 4
    )


def test_cost_cap_still_trips_with_cache_adjusted_cost():
    usage = {"inputTokens": 10_000_000, "outputTokens": 0}
    bedrock = FakeBedrock(
        [tool_use_response(usage), tool_use_response(usage), end_turn_response(usage)]
    )
    result = agent.run_agent(
        bedrock,
        "m",
        (0.000004, 0.00002),
        "sys",
        "hello",
        FakeToolbox(),
        params(max_run_cost_usd=1.0),
    )
    assert result["stopped"] == "cost_cap"


def test_turn_cap_still_applies():
    bedrock = FakeBedrock(
        [tool_use_response({"inputTokens": 1, "outputTokens": 1})] * 5
    )
    result = agent.run_agent(
        bedrock, "m", (1e-6, 1e-6), "sys", "hello", FakeToolbox(), params(max_turns=5)
    )
    assert result["stopped"] == "turn_cap" and result["turns"] == 5


def test_finished_reports_final_text():
    bedrock = FakeBedrock([end_turn_response({"inputTokens": 1, "outputTokens": 1})])
    result = agent.run_agent(
        bedrock, "m", (1e-6, 1e-6), "sys", "hello", FakeToolbox(), params()
    )
    assert result["stopped"] == "finished" and result["final_text"] == "done"
