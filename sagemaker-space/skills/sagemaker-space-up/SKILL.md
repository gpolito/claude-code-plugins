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

Exercised for real: `--create` with the wait loop (the app takes about 10 minutes to reach InService), the expired SSO login path (exit 2) and the ssh retries, including the two ways ssh fails after a create (see below).

Not exercised yet: exit 4 (app failed or wait timed out) and a custom `--wait N`. Treat those paths as untested and check the output.

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
| 5 | ssh failed | See "When ssh fails" below, then `references/ssh-host-setup.md` |
| 64 | Bad usage or config | Fix the config file |

## When ssh fails

The app can be `InService` and still refuse ssh. Two causes seen in practice:

- **Changed host key.** Happens when the app was started outside the script (for example from the web, or by the user), because only `--create` runs `ssh-keygen -R`. Run `ssh-keygen -R <SSH_HOST>` and retry. This was the cause when the first attempt failed and the second worked.
- **`Connection timed out during banner exchange`.** The SSM session opens but sshd does not answer. After a fresh create it lasted more than 25 minutes while the AWS health check was fine, and opening JupyterLab in the web did not fix it. Do not keep retrying. Ask the user to work from a terminal inside JupyterLab, or delete the app and create it again.

The AWS CLI login (`aws sso login`) is separate from the browser session of the space: logging in to the space on the web or from a phone does not renew the CLI token, and `up.sh` will still exit 2.

## Things to remember when working on the instance

- The app is deleted after the space's idle timeout (60 minutes by default). Files under `/home/sagemaker-user` live on the space's EBS volume and survive, but anything installed elsewhere is lost. Long runs may need an open JupyterLab terminal to count as activity.
- After a successful `--create` the script runs `ssh-keygen -R <SSH_HOST>`: a new app is a new machine with new host keys, and `StrictHostKeyChecking accept-new` would reject the old entry. This edits `~/.ssh/known_hosts` (ssh-keygen keeps a `.old` copy).
- Never run `ssh -v` through the proxy or print the proxy's output: the session JSON contains a one-time token.
- ssh stderr is silenced in the script on purpose, so a failure message may be missing. Rerun the proxy by hand to see it.
- Copying files over the SSM proxy is slow (about 1 MB/s) and can fail halfway without a clear error: a `tar` pipe once lost 103 of 1260 files and left one truncated. After an upload compare the number of files and their sizes with the source (`stat` on both sides and `diff`).
- A long run needs `setsid nohup ... &` on the instance so it survives the ssh session, and the app still shuts down after the idle timeout while it runs. Visiting the space on the web resets that timer.
- `~/.cache/uv` can grow to tens of GB on the 100 GB volume (41 GB once). If the disk fills up, `uv cache clean` frees it without touching the project.
