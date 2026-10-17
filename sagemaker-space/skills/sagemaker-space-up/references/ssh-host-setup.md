# ssh host for a SageMaker space (AWS CLI proxy, no browser)

Needs the AWS CLI, `session-manager-plugin` and an SSO profile that can call `sagemaker:StartSession` on the space. The space must have remote access enabled.

`~/.ssh/config`:

```
Host my-sagemaker-host
    User sagemaker-user
    ProxyCommand ~/.ssh/my-sagemaker-proxy.sh
    StrictHostKeyChecking accept-new
    ServerAliveInterval 30
```

`~/.ssh/my-sagemaker-proxy.sh` (`chmod 700`):

```bash
#!/bin/bash
set -euo pipefail
SPACE_ARN="arn:aws:sagemaker:<region>:<account>:space/<domain-id>/<space-name>"
REGION="<region>"
PROFILE="<sso-profile>"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH" AWS_PAGER=""

session_json="$(aws sagemaker start-session --resource-identifier "$SPACE_ARN" \
  --profile "$PROFILE" --region "$REGION" --output json)" || {
  echo "start-session failed: is the JupyterLab app running and the SSO login valid?" >&2
  exit 1
}
exec session-manager-plugin "$session_json" "$REGION" StartSession
```

Why not the AWS Toolkit for VS Code: its `sm_dl_*` hosts open a browser tab on every token refresh, and its `sm_lc_*` mode needs a mapping the Explorer only writes when it can resolve a Studio user profile (not possible with IAM domains and an SSO role). In my setup (Toolkit 4.17.0, macOS) that mode also failed: the server log showed `Cannot find module '../../../../130.js'`, a chunk that was not in the extension folder. Later versions may have fixed it.
