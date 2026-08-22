# Tk `console` command for Unix (TIP 561)

This repository contains the implementation and supporting tools for
[TIP 561](tip-561-draft.md), which brings the `console` command —
already available on Windows and macOS — to Tk on Linux/Unix.

Full background, rationale, and implementation details are in
[`tip-561-draft.md`](tip-561-draft.md). This README covers only how
to use the code in this repository.

## Using the console without waiting on the TIP

Should TIP 561 not be approved, or in the meantime before it is, the
console command can still be used on any Linux/Unix system by
manually sourcing the implementation and showing it:

```tcl
source consolecmd.impl
console show
```

No other changes to Tk are required for this to work.

## Remote console tools

This repository also includes a small set of tools built on top of
`console eval`, for mirroring and remotely driving a console running
on another machine (for example, a headless container). These were
built as a demonstration of what's possible on top of the console
command as specified in the TIP, and as genuinely useful debugging
utilities in their own right. None of them require any change to
`console` itself.

**Security note:** none of these servers implement authentication or
encryption. They are intended for use on a trusted network only
(localhost, an SSH tunnel, or an isolated container network) — never
expose one of these ports directly to an untrusted network. See below about setting up an ssh secure tunnel.

### Servers (run on the machine being observed/debugged)

| File | Port | Purpose |
|---|---|---|
| `consolesrv1.tcl` | 9998 | One-shot: on connect, sends the console's current contents as plain text, then closes. |
| `consolesrv2.tcl` | 9997 | Persistent, multi-connection remote-eval server. Compatible with tkcon's socket-attach (Host:/Port:) feature. Reads a command, evaluates it, and writes back the result — repeating until the client sends `done`. Buffers multi-line input using `info complete`, with a 2-second timeout on incomplete commands, so pasted multi-line code (e.g. a `proc`) works reliably. |
| `consolesrv3.tcl` | 9996 | One-shot: on connect, sends the console's full contents *with* tag information (colors, fonts), via the text widget's `dump` command, then closes. |

Source the appropriate file(s) into the running application whose
console you want to expose.

### Clients

| File | Pairs with | Purpose |
|---|---|---|
| `consoleclient1.tcl` | `consolesrv1.tcl` | `fetch1 <ip> [port 9998]` — fetches and displays the remote console's plain text contents in the local console. |
| `consoleclient3.tcl` | `consolesrv3.tcl` | `fetch3 <ip> [port 9996]` — fetches the remote console's full tagged contents (colors, fonts) and reconstructs it faithfully in the local console. Also provides `sendproc <procname> [ip] [port 9997]` (see below). |

### `sendproc`: sending a proc to a remote console

tkcon's socket-attach feature runs everything you type through Tcl's
`subst`, which silently corrupts backslash sequences that aren't
recognized Tcl escapes — for example `\d+` in a regular expression
becomes `d+`. This makes it unreliable for pasting Tcl source code
(such as a `proc` definition) into tkcon when attached via a socket.

`sendproc`, included in `consoleclient3.tcl`, works around this by
never going through tkcon at all. Define or paste the proc you want
to send into your own *local* console, then run:

```tcl
sendproc <procname> [ip] [port 9997]
```

This reconstructs the proc's real definition locally (via `info
args`/`info default`/`info body`, list-quoted for safety) and sends
it as a single, untouched write directly to a `consolesrv2` instance
— no `subst`, no risk of backslash corruption. If `ip` is omitted, it
defaults to the current value of the global `ipvar` (see the monitor
tool below); if that isn't set either, you'll get a clear connection
error rather than a silent failure.

### Console monitor

`consolemonitor_addon.tcl` is a small GUI that gives a near-live
mirror of a remote console. It polls the remote console's insert
position once a second over a persistent `consolesrv2` connection;
whenever that changes, it automatically calls `fetch3` to refresh the
local mirror — so any `puts`/`puts stderr` output produced by
commands run through tkcon (or anything else happening in the
target process) shows up locally, in the correct colors, without
needing to view the target machine's screen directly.

**On the remote (target) machine**, both `consolesrv2.tcl` and
`consolesrv3.tcl` need to be sourced into the running application
before the monitor can connect — the monitor uses `consolesrv2` for
polling/eval and `consolesrv3` for fetching the full tagged dump.

The GUI provides:

- an IP address entry (with a **Copy** button), backed by the global
  `ipvar`
- a **monitoring** checkbox — checking it connects to the remote and
  starts polling, with the very first poll always fetching regardless
  of whether anything has actually changed yet. Unchecking it closes
  the connection to `consolesrv2` and pauses monitoring entirely;
  re-checking it reconnects and resumes. Note that while monitoring
  is on, the local console's contents are replaced on every detected
  remote update — so if you're typing commands directly into the
  local console while monitoring is active, an update from the
  remote side could clear what you were entering.
- a **Clear Remote** button, which clears the remote console
- a note reminding you to use port 9997 in tkcon for the eval
  connection
- an **Exit** button

`consolemonitor_addon.tcl` already includes, at the end of the file,
the code needed to run it as a standalone, double-clickable script
(or via `wish <filename>`). It sources `consoleclient3.tcl`
automatically at startup (which must be in the same directory) and
sets a default IP address shown in the entry field — edit that
default directly in the script if your usual target machine's
address is different.

### Setting up a secure ssh tunnel

To setup a secure tunnel using ssh, the remote side needs to have ssh servers running, and the local side, running the monitoring client and Tkcon, needs only the ssh client.

The remote tcl program to be monitoring and debugged, needs to have sourced consolesrv2.tcl and consolesrv3.tcl and then run the following on the local end (the machine running the monitoring tool and/or tkcon):

```
    ssh -L 9997:localhost:9997 -L 9996:localhost:9996 user@remote-host
```

Replace user with an account on the remote machine, and remote-host with its address — either a hostname or a numeric IP both work. Any account with SSH login access on the remote machine can be used; the tunnel itself doesn't require any special privileges.

This opens ports 9997 and 9996 on your local machine, tunneled through an encrypted connection to the same ports on the remote machine. Once connected, point tkcon's socket-attach at 127.0.0.1, port 9997, and the monitoring tool's IP field at 127.0.0.1 as well (for port 9996) — both now route through the encrypted tunnel rather than connecting to the remote machine's address directly.

This command will then give you a prompt from the shell on the remote end. When you want to shut everything down, type

```
   exit
```
