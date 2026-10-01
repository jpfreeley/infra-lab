"""ntfy.sh push notifications. Failures are logged, never raised."""

import logging
import urllib.request

logger = logging.getLogger()


def _ascii(text):
    return text.encode("ascii", "ignore").decode("ascii")


def send(topic, title, message, priority=3, tags=""):
    """Publish a message to an ntfy topic. Returns True on success."""
    if not topic:
        logger.warning("ntfy topic missing, notification skipped")
        return False
    headers = {"Title": _ascii(title)[:120], "Priority": str(priority)}
    if tags:
        headers["Tags"] = _ascii(tags)
    request = urllib.request.Request(
        f"https://ntfy.sh/{topic.strip()}",
        data=message.encode("utf-8")[:3800],
        method="POST",
        headers=headers,
    )
    try:
        with urllib.request.urlopen(request, timeout=10):
            return True
    except Exception as exc:  # noqa: B902 - notification must never break a run
        logger.warning("ntfy send failed: %s", exc)
        return False
