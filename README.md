# tmate-corpo

`tmate-corpo` runs on the CORPO Mac. It keeps a background tmate session open on that CORPO Mac and publishes a simple `tmate-corpo` command to the USER Mac over SSH.

The USER runs `tmate-corpo` on their own Mac to connect into the current CORPO Mac tmate session. When the CORPO service restarts or creates a new tmate session, it rewrites the USER Mac command with the new tmate SSH command.

## Architecture

```mermaid
flowchart LR
  subgraph CORPO["CORPO Mac"]
    repo["tmate-corpo repo"]
    makeConfig["make config"]
    makeInstall["make install"]
    launchd["launchd service   com.tmate-corpo.agent"]
    service["bin/tmate-corpo-service"]
    tmate["background tmate session"]
  end

  subgraph USER["USER Mac"]
    remoteLogin["Remote Login enabled"]
    command["tmate-corpo command   USER_COMMAND_PATH"]
    userRun["USER runs:   tmate-corpo"]
  end

  repo --> makeConfig
  makeConfig -->|"checks SSH + command path"| remoteLogin
  repo --> makeInstall
  makeInstall --> launchd
  launchd --> service
  service --> tmate
  service -->|"SSH writes updated connector"| command
  userRun --> command
  command -->|"ssh <tmate-session>"| tmate
```

Run `make config`, `make install`, and service management commands on the CORPO Mac. Run only the generated `tmate-corpo` command on the USER Mac.

## Requirements

- macOS on the CORPO Mac running the service.
- `make` installed on the CORPO Mac. On macOS, install Xcode Command Line Tools if `make` is missing:

```bash
xcode-select --install
```

- `tmate` installed on the CORPO Mac:

```bash
brew install tmate
```

- Remote Login enabled on the USER Mac so CORPO can SSH into it:

```text
System Settings -> General -> Sharing -> Remote Login
```

## Install

On the CORPO Mac, configure the USER Mac once:

```bash
make config
```

This writes:

```text
.tmate-corpo.env
~/.tmate-corpo/env
```

It also checks whether the CORPO Mac can SSH into the USER Mac and whether the configured USER Mac command path is writable. If either check fails, it prints the exact next steps, such as running `ssh-copy-id user@user-mac.local` from CORPO or switching to a user-writable path.

You can also configure by editing `.tmate-corpo.env` directly. Start from:

```bash
cp .tmate-corpo.env.example .tmate-corpo.env
```

Then install and start the LaunchAgent:

```bash
make install
```

`make install` creates `~/bin` on the USER Mac if needed, writes the executable connector at `~/bin/tmate-corpo`, runs `chmod 0755`, and adds `$HOME/bin` to the USER Mac zsh startup files before it returns. The background service keeps that file updated when the CORPO tmate session changes.

By default, the USER Mac command is written to:

```text
~/bin/tmate-corpo
```

That path is resolved on the USER Mac under the SSH user's home directory and does not need sudo. Configure with:

```bash
USER_COMMAND_PATH='~/bin/tmate-corpo' make config
```

If `tmate-corpo` is not found in an already-open USER Mac terminal, open a new terminal or run:

```bash
source ~/.zshrc
```

You can always run it with the full path:

```bash
~/bin/tmate-corpo
```

## Use

On the USER Mac:

```bash
tmate-corpo
```

To print the raw tmate SSH command instead of connecting:

```bash
tmate-corpo --print
```

## Manage The Service

```bash
make config
make status
make doctor
make logs
make restart
make stop
make start
make uninstall
```

## Troubleshooting

If install fails with a USER Mac path error, first inspect the loaded config and remote path check:

```bash
make doctor
```

If `~/bin/tmate-corpo` is missing on the USER Mac but the service is configured, republish the current connector:

```bash
make publish
```

For the default USER home setup:

```bash
USER_MAC=macmini USER_COMMAND_PATH='~/bin/tmate-corpo' make config
make install
```

`make doctor` prints the resolved path on the USER Mac and reports whether the CORPO Mac can create or write it.

## Files

- `Makefile` is the public command surface.
- `bin/tmate-corpoctl` installs and controls the macOS LaunchAgent.
- `bin/tmate-corpo-service` is the long-running background service.
- `lib/common.sh` contains shared config, tmate, SSH, and connector publishing helpers.

The installer copies runtime files into:

```text
~/.tmate-corpo/
```

The LaunchAgent plist is written to:

```text
~/Library/LaunchAgents/com.tmate-corpo.agent.plist
```
