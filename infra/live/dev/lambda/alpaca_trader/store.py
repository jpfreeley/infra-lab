"""S3-backed state: handoff, journal, run lock, control flag, private config."""

import json
import time
from datetime import datetime, timezone

LOCK_TTL_SECONDS = 15 * 60


class LockHeldError(Exception):
    """Raised when another live run holds the lock."""


class Store:
    """Reads and writes run state under an optional key prefix."""

    def __init__(self, s3, bucket, prefix=""):
        """Bind to a bucket. A prefix isolates dry-run state from real state."""
        self.s3 = s3
        self.bucket = bucket
        self.prefix = prefix

    def _key(self, key):
        return f"{self.prefix}{key}"

    def get_text(self, key, default=None, absolute=False):
        """Read an object as text, or return default when it is missing."""
        full = key if absolute else self._key(key)
        try:
            body = self.s3.get_object(Bucket=self.bucket, Key=full)["Body"]
            return body.read().decode("utf-8")
        except self.s3.exceptions.NoSuchKey:
            return default

    def put_text(self, key, text, absolute=False):
        """Write text to an object."""
        full = key if absolute else self._key(key)
        self.s3.put_object(
            Bucket=self.bucket,
            Key=full,
            Body=text.encode("utf-8"),
            ServerSideEncryption="aws:kms",
        )

    def get_json(self, key, default=None, absolute=False):
        """Read and parse a JSON object."""
        text = self.get_text(key, None, absolute)
        return default if text is None else json.loads(text)

    def put_json(self, key, value, absolute=False):
        """Serialize and write a JSON object."""
        self.put_text(key, json.dumps(value, indent=2, sort_keys=True), absolute)

    def append_jsonl(self, key, entry):
        """Append one line to a JSONL object. Callers hold the run lock."""
        existing = self.get_text(key, "") or ""
        line = json.dumps(entry, sort_keys=True, default=str)
        self.put_text(key, existing + line + "\n")

    def tail_lines(self, key, count):
        """Return the last count lines of a text object."""
        text = self.get_text(key, "") or ""
        return text.splitlines()[-count:]

    # Lock ------------------------------------------------------------------

    def acquire_lock(self, run_id, slot):
        """Take the run lock or raise LockHeldError. Steals an expired lock."""
        key = self._key("state/lock.json")
        body = json.dumps(
            {
                "run_id": run_id,
                "slot": slot,
                "expires_at": time.time() + LOCK_TTL_SECONDS,
            }
        ).encode("utf-8")
        for _ in range(2):
            try:
                self.s3.put_object(
                    Bucket=self.bucket,
                    Key=key,
                    Body=body,
                    IfNoneMatch="*",
                    ServerSideEncryption="aws:kms",
                )
                return
            except self.s3.exceptions.ClientError as exc:
                code = exc.response.get("Error", {}).get("Code", "")
                if code not in ("PreconditionFailed", "ConditionalRequestConflict"):
                    raise
                current = self.get_json("state/lock.json", {}) or {}
                if current.get("expires_at", 0) > time.time():
                    raise LockHeldError(
                        f"lock held by {current.get('run_id')}"
                    ) from exc
                self.s3.delete_object(Bucket=self.bucket, Key=key)
        raise LockHeldError("could not acquire lock")

    def release_lock(self, run_id):
        """Release the lock only if this run still owns it."""
        current = self.get_json("state/lock.json", {}) or {}
        if current.get("run_id") == run_id:
            self.s3.delete_object(Bucket=self.bucket, Key=self._key("state/lock.json"))


def now_iso():
    """Return the current UTC time as an ISO 8601 string."""
    return datetime.now(timezone.utc).isoformat(timespec="seconds")
