#!/bin/bash
# Checks (and optionally starts) a SageMaker JupyterLab space and verifies the ssh host that reaches it.
# Only reads from AWS unless --create is given. Never prints session tokens.
set -uo pipefail

usage() {
  cat <<'USAGE'
Usage: up.sh [--create] [--dry-run] [--wait SECONDS] [--config FILE]

  --create       Start the JupyterLab app if it is Deleted/Failed/missing (costs money per hour).
  --dry-run      With --create: print the create-app command instead of running it.
  --wait N       Seconds to wait for the app to become InService (default 600).
  --config FILE  Config file (default: $SAGEMAKER_SPACE_CONFIG or ~/.config/sagemaker-space-up/default.conf).

Exit codes: 0 ready, 2 AWS login invalid, 3 app is down (rerun with --create),
            4 app failed or timed out, 5 ssh check failed, 64 bad usage/config.
USAGE
}

CONFIG_FILE="${SAGEMAKER_SPACE_CONFIG:-$HOME/.config/sagemaker-space-up/default.conf}"
CREATE=0
DRY_RUN=0
WAIT_SECONDS=600
while [ $# -gt 0 ]; do
  case "$1" in
    --create) CREATE=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --wait) WAIT_SECONDS="${2:?--wait needs a value}"; shift ;;
    --config) CONFIG_FILE="${2:?--config needs a value}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 64 ;;
  esac
  shift
done

if [ ! -f "$CONFIG_FILE" ]; then
  echo "Config file not found: $CONFIG_FILE (see config.example next to this script)" >&2
  exit 64
fi
set -a
# shellcheck disable=SC1090
. "$CONFIG_FILE"
set +a
for required in AWS_PROFILE_NAME REGION DOMAIN_ID SPACE_NAME SSH_HOST; do
  if [ -z "${!required:-}" ]; then
    echo "Missing $required in $CONFIG_FILE" >&2
    exit 64
  fi
done
APP_NAME="${APP_NAME:-default}"

aws_cmd() {
  AWS_PAGER="" aws "$@" --profile "$AWS_PROFILE_NAME" --region "$REGION"
}

app_status() {
  aws_cmd sagemaker describe-app --domain-id "$DOMAIN_ID" --space-name "$SPACE_NAME" \
    --app-type "$APP_TYPE" --app-name "$APP_NAME" --query Status --output text 2>/dev/null \
    || echo "NotFound"
}

wait_until_in_service() {
  local waited=0 status
  while [ "$waited" -lt "$WAIT_SECONDS" ]; do
    status="$(app_status)"
    case "$status" in
      InService) echo; return 0 ;;
      Failed|Deleted|NotFound) echo; echo "App ended in state $status while waiting." >&2; exit 4 ;;
    esac
    printf '.'
    sleep 10
    waited=$((waited + 10))
  done
  echo; echo "Timed out after ${WAIT_SECONDS}s waiting for the app (last state: $status)." >&2
  exit 4
}

# 1. AWS login
if ! account="$(aws_cmd sts get-caller-identity --query Account --output text 2>/dev/null)"; then
  echo "[1/4] AWS login for profile '$AWS_PROFILE_NAME' is not valid." >&2
  echo "      Run: aws sso login --profile $AWS_PROFILE_NAME" >&2
  exit 2
fi
echo "[1/4] AWS login OK (profile $AWS_PROFILE_NAME, account $account)"

# 2. Space
space_info="$(aws_cmd sagemaker describe-space --domain-id "$DOMAIN_ID" --space-name "$SPACE_NAME" \
  --query '[Status,SpaceSettings.RemoteAccess,SpaceSettings.AppType,SpaceSettings.JupyterLabAppSettings.AppLifecycleManagement.IdleSettings.IdleTimeoutInMinutes]' \
  --output text 2>&1)" || { echo "[2/4] Cannot describe space $SPACE_NAME: $space_info" >&2; exit 64; }
read -r space_status remote_access APP_TYPE idle_minutes <<<"$space_info"
[ "$APP_TYPE" = "None" ] && APP_TYPE="JupyterLab"
echo "[2/4] Space $SPACE_NAME: status=$space_status remote_access=$remote_access idle_shutdown=${idle_minutes}min"
if [ "$remote_access" != "ENABLED" ]; then
  echo "      Remote access is not ENABLED on this space; ssh will not work." >&2
fi

# 3. App
status="$(app_status)"
if [ "$status" = "Deleting" ]; then
  printf '[3/4] App is Deleting, waiting'
  while [ "$(app_status)" = "Deleting" ]; do printf '.'; sleep 10; done
  echo
  status="$(app_status)"
fi
case "$status" in
  InService)
    echo "[3/4] App $APP_TYPE/$APP_NAME is InService"
    ;;
  Pending)
    printf '[3/4] App is Pending, waiting'
    wait_until_in_service
    echo "[3/4] App is InService"
    ;;
  Deleted|Failed|NotFound)
    if [ "$CREATE" -ne 1 ]; then
      echo "[3/4] App $APP_TYPE/$APP_NAME is $status (stopped by idle shutdown or manually)." >&2
      echo "      Rerun with --create to start it (billed per hour), or start it from Studio." >&2
      exit 3
    fi
    resource_spec="$(aws_cmd sagemaker describe-space --domain-id "$DOMAIN_ID" --space-name "$SPACE_NAME" \
      --query 'SpaceSettings.JupyterLabAppSettings.DefaultResourceSpec' --output json 2>/dev/null | tr -d '\n' || echo null)"
    create_args=(sagemaker create-app --domain-id "$DOMAIN_ID" --space-name "$SPACE_NAME"
      --app-type "$APP_TYPE" --app-name "$APP_NAME")
    [ "$resource_spec" != "null" ] && create_args+=(--resource-spec "$resource_spec")
    if [ "$DRY_RUN" -eq 1 ]; then
      echo "[3/4] (dry run) would run: aws ${create_args[*]} --profile $AWS_PROFILE_NAME --region $REGION"
      exit 0
    fi
    echo "[3/4] App is $status, creating it with the space's default resource spec"
    aws_cmd "${create_args[@]}" --output text >/dev/null || { echo "create-app failed" >&2; exit 4; }
    printf '      Waiting for InService'
    wait_until_in_service
    echo "[3/4] App is InService"
    # A new app is a new machine with new ssh host keys; the old known_hosts entry would be rejected.
    ssh-keygen -R "$SSH_HOST" >/dev/null 2>&1
    ;;
  *)
    echo "[3/4] Unexpected app state: $status" >&2
    exit 4
    ;;
esac

# 4. ssh (the SSM agent can take a few seconds after the app turns InService)
remote_command="hostname; nvidia-smi -L 2>/dev/null | head -1; df -h /home/sagemaker-user | tail -1"
if [ -n "${REPO_PATH:-}" ]; then
  remote_command="$remote_command; git -C '$REPO_PATH' log --oneline -1"
fi
for attempt in 1 2 3 4 5 6; do
  if ssh_output="$(ssh -o BatchMode=yes -o ConnectTimeout=60 "$SSH_HOST" "$remote_command" 2>/dev/null)"; then
    echo "[4/4] ssh $SSH_HOST OK"
    echo "$ssh_output" | sed 's/^/      /'
    exit 0
  fi
  [ "$attempt" -lt 6 ] && { echo "[4/4] ssh not ready (attempt $attempt/6), retrying in 10s"; sleep 10; }
done
echo "[4/4] ssh $SSH_HOST failed. Check the Host entry in ~/.ssh/config and its ProxyCommand." >&2
exit 5
