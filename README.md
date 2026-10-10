# claude-code-plugins

My Claude Code plugins. This repository is also a plugin marketplace (`gpolito-plugins`).

## Plugins

| Plugin | What it does |
| --- | --- |
| `usage-limits-band` | One dim line above the prompt in the Claude desktop app: 5-hour and 7-day plan usage as rings, with percent and reset countdown. Updates after every turn. Desktop only. |

## Install

From a terminal session of `claude` (the desktop Code tab does not run `/plugin`):

```
claude plugin marketplace add /Users/gpolito/Code/claude-code-plugins
claude plugin install usage-limits-band@gpolito-plugins
```

Plugins installed at the user scope also load in local sessions the desktop app starts.

## Adding a plugin

Create a folder with `.claude-plugin/plugin.json` and `hooks/`, then add an entry to `.claude-plugin/marketplace.json` with `"source": "./<folder>"`. Check it with `claude plugin validate <folder>`.
