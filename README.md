# claude-code-plugins

My Claude Code plugins. This repository is also a plugin marketplace (`gpolito-plugins`).

## Plugins

| Plugin | What it does |
| --- | --- |
| `usage-limits-band` | One dim line above the prompt in the Claude desktop app: 5-hour and 7-day plan usage as rings, with percent and reset countdown. Updates after every turn. Desktop only. |
| `sagemaker-space` | Skill + script to check and bring up a SageMaker JupyterLab space: SSO login, app state, optional `create-app` (asks first, billed per hour) and an ssh round trip. |

## Install

From a terminal session of `claude` (the desktop Code tab does not run `/plugin`):

```
claude plugin marketplace add gpolito/claude-code-plugins
claude plugin install usage-limits-band@gpolito-plugins
```

Then run `/reload-plugins` or start a new session. To get later updates: `claude plugin marketplace update gpolito-plugins`.

Plugins installed at the user scope also load in local sessions the desktop app starts.

## Requirements

- `usage-limits-band`: Claude Code with mod support. It only renders in the Claude desktop app.
- `sagemaker-space`: AWS CLI v2, `session-manager-plugin`, `ssh` and `bash`, an AWS SSO profile allowed to use SageMaker, and an ssh host for the space (setup in `sagemaker-space/skills/sagemaker-space-up/references/ssh-host-setup.md`).

`usage-limits-band` was tested with the Claude desktop app 2.37337.1 and the `claude` CLI 2.1.296. Older versions are untested.

`sagemaker-space` was tested on macOS (bash 3.2) with AWS CLI 2.29 against one JupyterLab space. Linux is untested. Exercised with the real `create-app`, the wait loop, an expired SSO login (exit code 2) and the ssh retries. Not exercised yet: exit code 4 (app failed or wait timed out) and a custom `--wait`.

## Security

Mods run locally with your user permissions. Read the source (for example `usage-limits-band/hooks/register.tsx`) before installing.

`usage-limits-band` is UI-only: it reads your session's plan-usage numbers and draws them above the prompt. It adds no tools, does not alter prompts or permissions, and makes no network requests.

`sagemaker-space` runs `aws` and `ssh` with your own profile. By default it only reads. With `--create` it starts a JupyterLab app, which is billed per hour, and then removes the old host-key entry of your ssh host from `~/.ssh/known_hosts` (a new app is a new machine). Its config file is sourced by bash, so only point it at files you wrote. It talks only to AWS and to your ssh host. Read `sagemaker-space/skills/sagemaker-space-up/scripts/up.sh` before installing.

## Development

To work on a plugin from a local clone, add the marketplace from its folder instead:

```
claude plugin marketplace add /path/to/claude-code-plugins
```

## Adding a plugin

Create a folder with `.claude-plugin/plugin.json` and `hooks/`, then add an entry to `.claude-plugin/marketplace.json` with `"source": "./<folder>"`. Check it with `claude plugin validate <folder>`.

## License

[MIT](LICENSE)
