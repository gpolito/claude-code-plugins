---
name: sagemaker-space-up
description: Bring up and verify the ssh connection to a SageMaker JupyterLab space. Use when the user wants to connect to or work on the SageMaker instance, asks to "levantar la conexión" or "conectar a la instancia", when ssh to the space fails, or when the JupyterLab app was shut down by idle timeout.
---

# Bring up a SageMaker space connection

The space is reached over ssh through an SSM proxy host defined in `~/.ssh/config`. This skill checks every link of that chain and starts the JupyterLab app when it is down.

## Run it

The script sits in `scripts/` next to this file (the skill's base directory is shown when it loads):

```bash
<base dir>/scripts/up.sh            # check only, changes nothing
<base dir>/scripts/up.sh --create   # also start the app if it is down
```

It reads `~/.config/sagemaker-space-up/default.conf` (override with `--config FILE` or `SAGEMAKER_SPACE_CONFIG`). `scripts/config.example` lists the keys. If the file does not exist, create it with the user, never invent values.

It checks, in order: AWS SSO login, space status and idle timeout, app state, and an `ssh` round trip (hostname, GPU, disk, last commit of `REPO_PATH`).

## Status

Not exercised yet: the real `create-app` (only `--dry-run`), the expired SSO login path (exit 2), the wait loop and the ssh retries. Treat those paths as untested and check the output.

## Decisions that belong to the user

- **Starting the app (`--create`)** bills per hour for the instance type. Run the check first, tell the user the app is down and ask before using `--create`. Use `--create --dry-run` to show the exact command.
- **SSO login** opens a browser, so ask the user to run `aws sso login --profile <profile>` themselves.
- Do not change the idle shutdown time of the space.

## Exit codes

| Code | Meaning | Next step |
| --- | --- | --- |
| 0 | Ready | Run commands with `ssh <SSH_HOST> '...'` |
| 2 | AWS login invalid | Ask the user to run `aws sso login` |
| 3 | App is Deleted/Failed | Ask, then rerun with `--create` |
| 4 | App failed or timed out | Look at the state with `aws sagemaker describe-app` |
| 5 | ssh failed | Check the Host entry and proxy, see `references/ssh-host-setup.md` |
| 64 | Bad usage or config | Fix the config file |

## Things to remember when working on the instance

- The app is deleted after the space's idle timeout (60 minutes by default). Files under `/home/sagemaker-user` live on the space's EBS volume and survive, but anything installed elsewhere is lost. Long runs may need an open JupyterLab terminal to count as activity.
- After a successful `--create` the script runs `ssh-keygen -R <SSH_HOST>`: a new app is a new machine with new host keys, and `StrictHostKeyChecking accept-new` would reject the old entry. This edits `~/.ssh/known_hosts` (ssh-keygen keeps a `.old` copy).
- Never run `ssh -v` through the proxy or print the proxy's output: the session JSON contains a one-time token.
- ssh stderr is silenced in the script on purpose, so a failure message may be missing. Rerun the proxy by hand to see it.
