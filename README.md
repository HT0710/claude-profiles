# claude-profiles

`cl` runs several Claude Code accounts side by side on one machine. Each account lives in its own config folder, and `cl` shows the usage left on each one, picks the best one to use next, and opens it.

```text
 ◆ Claude profiles  4 profiles · 15:28

   name   account                      5-hour                      weekly
   main   work@example.com             ━━━━━━━━━━━━   0% 3h 25m    ━━━━━━━━━━━━  94% 1d 19h
▌  b      me@example.com               ━━━━━━━━━━━━   9% 4h 25m    ━━━━━━━━━━━━  77% 4d 4h     ★ best
   c      alt@example.com              ━━━━━━━━━━━━   2% 4h 15m    ━━━━━━━━━━━━ 100% 25m       ● full
   d      (no login)

    open  ↑↓ ⏎ select  1-9 number  c resume  a auto     manage  h hold  n new  x remove  w swap  s sync     more  b bypass  t ttl  r refresh  q quit
```

## Install

It is one bash file. It needs `bash` 3.2 or later, `curl`, `jq` and `claude`.

```bash
mkdir -p ~/.local/bin
curl -fsSL https://raw.githubusercontent.com/HT0710/claude-profiles/main/cl -o ~/.local/bin/cl
chmod +x ~/.local/bin/cl
```

Make sure `~/.local/bin` is in your `PATH`. On macOS, install `jq` with `brew install jq` if it is missing.

### Zsh completion

`_cl` completes commands with descriptions, profile names and hold times. Put it in a folder in your `fpath`, then register it in `~/.zshrc`:

```bash
mkdir -p ~/.zsh/completions
curl -fsSL https://raw.githubusercontent.com/HT0710/claude-profiles/main/_cl -o ~/.zsh/completions/_cl
```

```zsh
fpath=(~/.zsh/completions $fpath)   # before compinit or oh-my-zsh
autoload -Uz _cl && compdef _cl cl  # after compinit
```

If you cloned the repo, link the file instead of downloading it, so `git pull` keeps it current: `ln -s ~/claude-profiles/_cl ~/.zsh/completions/_cl`.

## How profiles work

- `main` is the default `~/.claude` folder.
- Every other profile is a folder named `~/.claude-<name>` that holds a Claude Code login or config. Other `~/.claude-*` folders are ignored. `cl` starts Claude Code with `CLAUDE_CONFIG_DIR` pointing at it.
- Each profile keeps its own login, `.claude.json`, cache and backups.
- Everything else in `~/.claude` is linked into each profile, so settings, `CLAUDE.md`, hooks, history and projects are shared. Links are added before each launch and never replace a file that already exists.
- To rename a profile, close its sessions and run `mv ~/.claude-a ~/.claude-b`. A hold on `a` does not move, so hold `b` again if needed.

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
| `cl ttl [5m\|1h\|default]` | Shows or sets the prompt cache TTL. Also `t` in the menu. |
| `cl hold <name> [release\|reset\|week\|30m\|2h\|1d]` | Keeps a profile out of `★ best` and `cl auto`. Also `h` in the menu. |
| `cl release <name>` | Ends a hold. |

## Picking the best profile

`cl` picks the profile whose weekly usage would go to waste fastest: the highest weekly percent left divided by the hours until the weekly reset. Profiles with less than 5% of the week left are skipped. Profiles whose 5-hour window is at 80% or more are skipped too, because a session there would soon stop. If no other profile qualifies, one whose 5-hour window resets within 30 minutes is picked instead.

A profile at 90% or more of its 5-hour window that isn't the best pick shows `◌ wait` with the time until its window resets.

## Resume

All profiles share `~/.claude/projects`, so a session started in one profile can be resumed in another, for example after a limit is hit. Press `c` in the menu, or run `cl <name> -r` or `cl auto -r`, to open Claude Code's session picker.

## Hold

A held profile is never `★ best`, and `cl auto` skips it. You can still open it with `cl <name>`. The table shows `⏸ held` and, for a timed hold, the time left.

- `cl hold b`, or `cl hold b release`, lasts until `cl release b`.
- `cl hold b reset` lasts until b's 5-hour window resets, and `cl hold b week` until its weekly limit resets. Both fail if b has no reset time, for example an unused window or a key profile.
- `cl hold b 2h` lasts that long. `30m` and `1d` also work.
- In the menu, `h` releases a held profile. Otherwise it asks how long to hold it, with the same words; Enter cancels.

Holds are saved in `~/.config/cl/config`.

## Bypass mode

With `cl bypass on`, every launch from `cl` adds `--dangerously-skip-permissions`, so Claude Code runs commands and edits files without asking. The menu title shows `bypass on` in red while it is on. The setting is saved in `~/.config/cl/config` and is off until you turn it on.

## Prompt cache TTL

`cl ttl 1h` makes every launch from `cl` set `CLAUDE_CODE_PROMPT_CACHE_TTL=1h`, so Claude Code keeps its prompt cache for an hour instead of the default. `cl ttl default` stops setting it. The menu title shows `cache 1h` while it is set, and `t` cycles default, 5m and 1h. The setting is saved in `~/.config/cl/config`. It needs Claude Code 2.1.242 or later, and 1-hour cache writes cost more.

For one run, put `--ttl` before or right after the profile name or `auto`, as in `cl --ttl 5m b`, `cl b --ttl 5m` or `cl auto --ttl 1h -c`; `--ttl=5m` also works. `cl --ttl 1h` alone opens the menu, and every profile opened from it uses 1h. It overrides `cl ttl` and any `CLAUDE_CODE_PROMPT_CACHE_TTL` you exported. An exported value also overrides `cl ttl`, and the menu title then shows it as `cache 5m (env)`.

## OpenRouter key profile

A profile can use an OpenRouter API key instead of a claude.ai login. To set one up, run `mkdir ~/.claude-<name>`, then `touch ~/.claude-<name>/.cl-profile`, then write `~/.claude-<name>/openrouter.json` with mode 600. That file holds the settings that differ from main, such as `model` and an `env` block with `ANTHROPIC_BASE_URL=https://openrouter.ai/api` and `ANTHROPIC_AUTH_TOKEN=<key>`.

- Before each launch and on `cl sync`, `settings.json` is rebuilt as main's settings plus `openrouter.json`, so changes to main's settings carry over. A `/model` choice saved in that profile is overwritten; put the model in `openrouter.json` instead.
- `cl ls` shows the key's spend, limit and reset time from OpenRouter. The key is sent only on `curl`'s standard input, so it never shows in `ps`.
- `★ best` and `cl auto` pick a key profile only when no account is usable now, because accounts are prepaid and a key is billed per use. An account whose 5-hour window resets within 30 minutes comes after the key. A key at its spend limit, or whose spend failed to load, is never picked.

## Swap

`cl swap a b` exchanges the login and account data of two profiles, so that, for example, plain `claude` uses another account. Projects and settings stay where they are. Both profiles are backed up first as `*.bak-cl-<time>`, and running the same swap again undoes it.

In the menu, `w` marks the selected profile with `⇄ from`. Move to the other profile with ↑↓ and press Enter to swap, or Esc to cancel.

If Claude Code is open on either profile, `cl` lists those sessions and asks before going on. A running session keeps its old account and may write its login back when its token renews, so close them first when you can.

## Limits

- **Usage numbers** come from an undocumented endpoint, `api.anthropic.com/api/oauth/usage`, so they may stop working without notice. To read them, `cl` sends each profile's own login token to `api.anthropic.com` and nowhere else.
- **Expired tokens** are renewed by `cl`, which runs `claude auth status` for that profile. No model is called, so no usage is spent. If the renewal fails, the profile shows `expired, open once`, has no usage numbers, and `★ best` and `cl auto` skip it.
- **macOS** keeps logins in the Keychain. Usage for `main` should work, but the Keychain name for other profiles is a guess, and `swap` is not supported. macOS support has not been tested yet.

## License

MIT
