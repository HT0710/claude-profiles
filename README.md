# claude-profiles

`cl` runs several Claude Code accounts side by side on one machine. Each account lives in its own config folder, and `cl` shows the usage left on each one, picks the best one to use next, and opens it.

```text
 ◆ Claude profiles  4 profiles · 15:28

   name   account                      5-hour                      weekly
   main   work@example.com             ━━━━━━━━━━━━   0% 3h 25m    ━━━━━━━━━━━━  94% 1d 19h
▌  b      me@example.com               ━━━━━━━━━━━━   9% 4h 25m    ━━━━━━━━━━━━  77% 4d 4h     ★ best
   c      alt@example.com              ━━━━━━━━━━━━   2% 4h 15m    ━━━━━━━━━━━━ 100% 25m       ● full
   d      (no login)

 ↑↓ move   ⏎ open   1-9 open   c resume   a auto   b bypass   n new   x remove   w swap   s sync   r refresh   q quit
```

## Install

It is one bash file. It needs `bash` 3.2 or later, `curl`, `jq` and `claude`.

```bash
mkdir -p ~/.local/bin
curl -fsSL https://raw.githubusercontent.com/HT0710/claude-profiles/main/cl -o ~/.local/bin/cl
chmod +x ~/.local/bin/cl
```

Make sure `~/.local/bin` is in your `PATH`. On macOS, install `jq` with `brew install jq` if it is missing.

## How profiles work

- `main` is the default `~/.claude` folder.
- Every other profile is a folder named `~/.claude-<name>` that holds a Claude Code login or config. Other `~/.claude-*` folders are ignored. `cl` starts Claude Code with `CLAUDE_CONFIG_DIR` pointing at it.
- Each profile keeps its own login, `.claude.json`, cache and backups.
- Everything else in `~/.claude` is linked into each profile, so settings, `CLAUDE.md`, hooks, history and projects are shared. Links are added before each launch and never replace a file that already exists.

## Commands

| command | what it does |
|---|---|
| `cl` | Opens the menu. |
| `cl <name> [args]` | Opens a profile. Extra arguments go to `claude`, so `cl c -r` resumes a session. |
| `cl auto [args]` | Opens the best profile, as marked with `★ best`. |
| `cl ls [-r]` | Prints the usage table. Results are cached for 60 seconds; `-r` skips the cache. |
| `cl new <name>` | Creates `~/.claude-<name>` and opens it so you can log in. |
| `cl sync [-n]` | Links missing shared files into every profile. `-n` only lists them. |
| `cl rm <name>` | Moves a profile folder to the trash after you type its name. |
| `cl swap <a> <b>` | Exchanges the logins of two profiles. Linux only. |
| `cl bypass [on\|off]` | Shows or sets bypass mode. Also `b` in the menu. |

## Picking the best profile

`cl` picks the profile whose weekly usage would go to waste fastest: the highest weekly percent left divided by the hours until the weekly reset. Profiles with less than 5% of the week left are skipped. Profiles whose 5-hour window is at 80% or more are skipped too, because a session there would soon stop. If no other profile qualifies, one whose 5-hour window resets within 30 minutes is picked instead.

## Resume

All profiles share `~/.claude/projects`, so a session started in one profile can be resumed in another, for example after a limit is hit. Press `c` in the menu, or run `cl <name> -r` or `cl auto -r`, to open Claude Code's session picker.

## Bypass mode

With `cl bypass on`, every launch from `cl` adds `--dangerously-skip-permissions`, so Claude Code runs commands and edits files without asking. The menu title shows `bypass on` in red while it is on. The setting is saved in `~/.config/cl/config` and is off until you turn it on.

## OpenRouter key profile

A profile can use an OpenRouter API key instead of a claude.ai login. To set one up, run `mkdir ~/.claude-<name>`, then `touch ~/.claude-<name>/.cl-profile`, then write `~/.claude-<name>/openrouter.json` with mode 600. That file holds the settings that differ from main, such as `model` and an `env` block with `ANTHROPIC_BASE_URL=https://openrouter.ai/api` and `ANTHROPIC_AUTH_TOKEN=<key>`.

- Before each launch and on `cl sync`, `settings.json` is rebuilt as main's settings plus `openrouter.json`, so changes to main's settings carry over. A `/model` choice saved in that profile is overwritten; put the model in `openrouter.json` instead.
- `cl ls` shows the key's spend, limit and reset time from OpenRouter. The key is sent only on `curl`'s standard input, so it never shows in `ps`.
- `★ best` and `cl auto` pick a key profile only when no account is usable now, because accounts are prepaid and a key is billed per use. An account whose 5-hour window resets within 30 minutes comes after the key. A key at its spend limit, or whose spend failed to load, is never picked.

## Swap

`cl swap a b` exchanges the login and account data of two profiles, so that, for example, plain `claude` uses another account. Projects and settings stay where they are. Both profiles are backed up first as `*.bak-cl-<time>`, and running the same swap again undoes it.

If Claude Code is open on either profile, `cl` lists those sessions and asks before going on. A running session keeps its old account and may write its login back when its token renews, so close them first when you can.

## Limits

- **Usage numbers** come from an undocumented endpoint, `api.anthropic.com/api/oauth/usage`, so they may stop working without notice. To read them, `cl` sends each profile's own login token to `api.anthropic.com` and nowhere else.
- **Expired tokens** are renewed by `cl`, which runs `claude auth status` for that profile. No model is called, so no usage is spent. If the renewal fails, the profile shows `expired, open once`, has no usage numbers, and `★ best` and `cl auto` skip it.
- **macOS** keeps logins in the Keychain. Usage for `main` should work, but the Keychain name for other profiles is a guess, and `swap` is not supported. macOS support has not been tested yet.

## License

MIT
