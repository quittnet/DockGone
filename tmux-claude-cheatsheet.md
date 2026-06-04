# 🚀 Claude + tmux Cheat Sheet

Run Claude on your server so tasks keep going even when you close Terminus / lock your phone.

---

## ⚡ The 3 commands you actually need

```bash
# 1. Start (or re-open) a session, then launch Claude
tmux new -A -s claude -c /root/code/linux_repo
claude

# 2. Walk away → just close Terminus. It keeps running.

# 3. Come back later
tmux attach -t claude
```

That's the whole workflow. Everything below is extra.

---

## 🏷️ My project aliases

| Alias | What it does |
|-------|--------------|
| `linux` | `cd /root/code/linux_repo && claude` |
| `wiki`  | `cd /root/my-wiki && claude` |
| `lectern` | (your lectern command) |

### Make them real aliases
Add these to `~/.bashrc` (or `~/.zshrc`), then run `source ~/.bashrc`:

```bash
alias linux='cd /root/code/linux_repo && claude'
alias wiki='cd /root/my-wiki && claude'
```

Now just type `linux` or `wiki` to jump in and launch Claude. 🎉

### 🔥 Better: aliases that run inside tmux automatically
These start/attach a tmux session **and** launch Claude in one word — so the task survives disconnects with zero extra steps:

```bash
alias linux='tmux new -A -s linux -c /root/code/linux_repo claude'
alias wiki='tmux new -A -s wiki  -c /root/my-wiki    claude'
```

- Type `linux` → drops you straight into Claude, inside a tmux session named `linux`.
- Close Terminus → it keeps running.
- Type `linux` again later → reattaches to the exact same session.

---

## 🧭 tmux essentials

| Action | Command / Keys |
|--------|----------------|
| List all sessions | `tmux ls` |
| Reattach to one | `tmux attach -t <name>` |
| Detach (leave it running) | `Ctrl-b` then `d` |
| Switch between sessions (inside tmux) | `Ctrl-b` then `s` |
| Rename current session | `Ctrl-b` then `$` |
| Kill a session | `tmux kill-session -t <name>` |

> **The detach move:** press `Ctrl-b`, let go, then press `d`. On Terminus, `Ctrl` is on the key row above the keyboard.

---

## 📱 iPhone / Terminus flow

1. Open Terminus → tap your server.
2. Type your alias (e.g. `linux`).
3. Give Claude the task.
4. Close Terminus and go about your day.
5. Reconnect anytime → type the same alias to pick up where it left off.

---

## 💡 Tips

- **Don't get blocked on prompts while away:** launch with
  `claude --permission-mode acceptEdits` so it doesn't pause to ask about edits.
- **Which session am I in?** Look at the far-left of the green bar at the bottom of the screen.
- **Forgot the session name?** `tmux ls` lists them all; `(attached)` marks the one you're in.
- **One session per project** keeps things clean — name them after the project (`linux`, `wiki`, etc.).
