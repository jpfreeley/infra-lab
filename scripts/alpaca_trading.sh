#!/usr/bin/env bash
# Control script for the scheduled paper trading runner.
#
#   alpaca_trading.sh set-secret alpaca|ntfy   Prompt silently, store in Secrets Manager
#   alpaca_trading.sh sync-config DIR          Upload private config from DIR to S3
#   alpaca_trading.sh enable START END         Allow scheduled runs (YYYY-MM-DD dates)
#   alpaca_trading.sh disable                  Stop scheduled runs immediately
#   alpaca_trading.sh status                   Show control flag and config presence
#   alpaca_trading.sh invoke SLOT [--dry-run]  Invoke one slot now (dry run simulates writes)
#
# Nothing sensitive is stored in this repo. Strategy text, prompts and limits
# live in DIR (kept outside git) and are uploaded to the private state bucket.
set -euo pipefail

# Always target the infra-lab account. An ambient AWS_PROFILE or static AWS
# credentials in the caller's shell (for example a different project's profile)
# are deliberately ignored, and the account id is verified before any call.
PROFILE="${ALPACA_TRADING_AWS_PROFILE:-infra-lab}"
REGION="us-east-1"
EXPECTED_ACCOUNT="551452024305"
unset AWS_PROFILE AWS_DEFAULT_PROFILE AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
BUCKET="infra-lab-dev-alpaca-trading"
FUNCTION="infra-lab-dev-alpaca-trader"
ALPACA_SECRET="infra-lab/alpaca-trading/alpaca-paper-keys"
NTFY_SECRET="infra-lab/alpaca-trading/ntfy-topic"

aws_cli() {
  aws --profile "$PROFILE" --region "$REGION" "$@"
}

verify_account() {
  local actual
  actual="$(aws_cli sts get-caller-identity --query Account --output text 2>/dev/null || true)"
  if [[ "$actual" != "$EXPECTED_ACCOUNT" ]]; then
    echo "Refusing to run: expected AWS account $EXPECTED_ACCOUNT but got '${actual:-none}'." >&2
    echo "Log in with: aws sso login --profile $PROFILE" >&2
    exit 1
  fi
}

usage() {
  sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
  exit 1
}

set_secret() {
  case "${1:-}" in
    alpaca)
      read -r -p "Alpaca PAPER key id: " key_id
      read -r -s -p "Alpaca PAPER secret key (hidden): " secret_key
      echo
      KEY_ID="$key_id" SECRET_KEY="$secret_key" python3 -c \
        'import json, os; print(json.dumps({"key_id": os.environ["KEY_ID"], "secret_key": os.environ["SECRET_KEY"]}))' |
        aws_cli secretsmanager put-secret-value \
          --secret-id "$ALPACA_SECRET" --secret-string file:///dev/stdin >/dev/null
      ;;
    ntfy)
      read -r -s -p "ntfy topic (hidden): " topic
      echo
      printf '%s' "$topic" |
        aws_cli secretsmanager put-secret-value \
          --secret-id "$NTFY_SECRET" --secret-string file:///dev/stdin >/dev/null
      ;;
    *) usage ;;
  esac
  echo "Secret stored."
}

sync_config() {
  local dir="${1:-}"
  [[ -d "$dir" ]] || { echo "config directory required" >&2; exit 1; }
  for f in STRATEGY.md GUARDRAILS.md config/guardrails.json; do
    [[ -f "$dir/$f" ]] || { echo "missing $dir/$f" >&2; exit 1; }
  done
  aws_cli s3 cp "$dir/STRATEGY.md" "s3://$BUCKET/config/STRATEGY.md"
  aws_cli s3 cp "$dir/GUARDRAILS.md" "s3://$BUCKET/config/GUARDRAILS.md"
  aws_cli s3 cp "$dir/config/guardrails.json" "s3://$BUCKET/config/guardrails.json"
  aws_cli s3 sync "$dir/prompts" "s3://$BUCKET/config/prompts" --delete
}

enable_runs() {
  local start="${1:-}" end="${2:-}"
  [[ "$start" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ && "$end" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] ||
    { echo "usage: enable YYYY-MM-DD YYYY-MM-DD" >&2; exit 1; }
  printf '{"enabled": true, "start_date": "%s", "end_date": "%s"}' "$start" "$end" |
    aws_cli s3 cp - "s3://$BUCKET/control/enabled.json"
  echo "Enabled from $start through $end."
}

disable_runs() {
  aws_cli s3 rm "s3://$BUCKET/control/enabled.json" || true
  echo "Disabled."
}

show_status() {
  echo "control flag:"
  aws_cli s3 cp "s3://$BUCKET/control/enabled.json" - 2>/dev/null || echo "  (absent: runs are disabled)"
  echo
  echo "private config objects:"
  aws_cli s3 ls "s3://$BUCKET/config/" --recursive || true
  echo
  echo "journals:"
  aws_cli s3 ls "s3://$BUCKET/journal/" || true
}

invoke_slot() {
  local slot="${1:-}" payload out
  [[ "$slot" =~ ^[1-6]$ ]] || usage
  payload="{\"slot\": $slot}"
  if [[ "${2:-}" == "--dry-run" ]]; then
    payload="{\"slot\": $slot, \"dry_run\": true}"
  fi
  out="$(mktemp)"
  aws_cli lambda invoke --function-name "$FUNCTION" \
    --cli-binary-format raw-in-base64-out --payload "$payload" "$out" >/dev/null
  cat "$out"
  echo
  rm -f "$out"
}

cmd="${1:-}"
shift || true
case "$cmd" in
  set-secret | sync-config | enable | disable | status | invoke) verify_account ;;
esac
case "$cmd" in
  set-secret) set_secret "$@" ;;
  sync-config) sync_config "$@" ;;
  enable) enable_runs "$@" ;;
  disable) disable_runs ;;
  status) show_status ;;
  invoke) invoke_slot "$@" ;;
  *) usage ;;
esac
