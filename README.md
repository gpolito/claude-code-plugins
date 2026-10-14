# claude-code-plugins

My Claude Code plugins. This repository is also a plugin marketplace (`gpolito-plugins`).

## Plugins

| Plugin | What it does |
| --- | --- |
| `usage-limits-band` | One dim line above the prompt in the Claude desktop app: 5-hour and 7-day plan usage as rings, with percent and reset countdown. Updates after every turn. Desktop only. |

## Install

From a terminal session of `claude` (the desktop Code tab does not run `/plugin`):

```
claude plugin marketplace add gpolito/claude-code-plugins
claude plugin install usage-limits-band@gpolito-plugins
```

Then run `/reload-plugins` or start a new session. To get later updates: `claude plugin marketplace update gpolito-plugins`.

Plugins installed at the user scope also load in local sessions the desktop app starts.

## Requirements

- Claude Code with mod support.
- `usage-limits-band` only renders in the Claude desktop app.

Tested with the Claude desktop app 2.37337.1 and the `claude` CLI 2.1.296. Older versions are untested.

## Security

Mods run locally with your user permissions. Read the source (for example `usage-limits-band/hooks/register.tsx`) before installing.

`usage-limits-band` is UI-only: it reads your session's plan-usage numbers and draws them above the prompt. It adds no tools, does not alter prompts or permissions, and makes no network requests.

## Development

To work on a plugin from a local clone, add the marketplace from its folder instead:

```
claude plugin marketplace add /path/to/claude-code-plugins
```

## Adding a plugin

Create a folder with `.claude-plugin/plugin.json` and `hooks/`, then add an entry to `.claude-plugin/marketplace.json` with `"source": "./<folder>"`. Check it with `claude plugin validate <folder>`.

## License

[MIT](LICENSE)
