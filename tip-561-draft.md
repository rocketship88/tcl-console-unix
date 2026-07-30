# TIP 561: Add console Command to Unix

	Author:         Eric Taylor <[email protected]>
	State:          Draft
	Type:           Project
	Vote:           Pending
	Created:        23-Jan-2020
	Post-History:
	Tcl-Version:    9.1
	Keywords:       Tk
	Tk-Branch:      tip-561
------

# Abstract

This TIP proposes that the `console` command be made an official, supported
command for Linux and other Unix platforms (hereafter called Unix). A console
can currently be run under Unix, but it requires additional code that is not
part of Tk itself. This TIP proposes that official support be given for the
`console` command on Unix, using Tcl's existing autoloading mechanism
(`tclIndex`), with no changes required to Tk's C core and no changes at all to
the existing Windows or Mac implementations.

# Rationale and Discussion

In [the Tcl'ers Wiki](https://wiki.tcl-lang.org/page/console+for+Unix), there
is a submitted code block that adds a `console` command and text window to a
Tcl/Tk program on Unix. This works well and has been available since 2005.
However, it is not supported "out of the box" - a developer has to find the
code, source it themselves, and rely on it continuing to work.

The wiki code itself notes that it depends on some undocumented Tk internals
and could break in a future release. Since this code has worked reliably for
20 years and is in real, ongoing use (see below), it seems worth making it an
official, supported feature on Unix rather than leaving it as an informally
shared script.

This TIP would eliminate an existing incompatibility between platforms and
protect this code from breakage in future releases.

An earlier draft of this TIP proposed a core-level stub command using
`vwait`/`tailcall` to defer setup until first use. Discussion on the tcl-core
list pointed out that Tcl already has a mechanism built for exactly this -
`tclIndex`-based autoloading - which is what every other on-demand command in
`tk/library` already uses (`tk_chooseColor`, `tk::fontchooser`, and many
others). This revision uses that existing mechanism instead of introducing a
new one.

# Proposal

Two files are added to `tk/library`:

- `consolecmd.tcl` - a small stub, safe for `auto_mkindex` to source directly.
  It creates one namespace, sets one path variable, and defines one proc. No
  interpreter is created and no window is built at this point - nothing runs
  until `console` is actually called for the first time.
- `consolecmd.impl` - the real implementation (the wiki code, cleaned up -
  see Implementation below). This is given a non-`.tcl` extension
  deliberately, so that `auto_mkindex`'s default `*.tcl` scan does not source
  it directly, since it does real work (creating an interpreter, loading Tk)
  as soon as it is sourced.

One line is added to the existing `tk/library/tclIndex`:

```
set auto_index(console) [list source [file join $dir consolecmd.tcl]]
```

No special setup is required to use the `console` command. The first time
`console` is called, Tcl's normal `unknown`/autoload mechanism sources
`consolecmd.tcl`, which in turn loads `consolecmd.impl` and forwards the
original call to it. From that point on, `console` behaves as a normal,
permanently-defined command, exactly like any other autoloaded Tk command.

Until `console` is called for the first time, stdout and stderr continue to
go to the terminal window where `wish` was invoked, unchanged from current
behavior.

The existing `console.tcl` (the shared script that defines the console
window's own behavior - text widget, menus, bindings - used by Windows and
Mac as well as this new Unix support) is not modified at all. Windows and Mac
are unaffected by this proposal.

## Differences in Behavior Across Systems

Currently on Unix, stdout/stderr always go to the terminal, and there is no
`console` command at all. After this change, the first call to `console`
(even a bad one, such as `console foobar`) triggers the one-time setup
described above - a hidden console interpreter and window are created - but
stdout/stderr are not yet redirected, and nothing is visible; output
continues to go to the terminal exactly as before. Only an explicit `console
show` redirects output and shows the window.

This matters more on Unix than it might elsewhere: many Unix Tk users have
never had a console command available at all, and are used to `wish`
behaving exactly like any other program run from a terminal. Keeping that
behavior completely unchanged by default - until a script or user explicitly
asks for a console - avoids surprising a large group of users who have no
existing expectation of this feature, while still making it available to
those who want it.

Once `console show` has been called, stdout/stderr are redirected to the
console window until the window is closed (via the window's close button)
or `console hide` is called, at which point output reverts to the terminal.

# Implementation

The following has been implemented and tested (Linux, both from `wish` and
from `tclsh` with Tk loaded via `package require Tk`), fixing several issues
found during testing beyond the original wiki code:

- The console window no longer flashes visible as a side effect of loading;
  it stays hidden until `console show` is explicitly called (including when
  the very first call is a bad one, e.g. `console foobar`).
- Calling `console show` more than once while already open no longer stacks
  duplicate `chan push` transforms on stdout/stderr - a bug in the original
  wiki code that could leave output silently redirected into a hidden
  console instead of the terminal after closing the window.
- A bare `console` call, or an unrecognized subcommand, now gives a normal
  Tcl-style error message rather than a raw argument-count error.
- Closing the console window (via its close button) reliably restores
  normal terminal output, confirmed even under `rlwrap`.
- Multi-byte Unicode output was garbled under the channel-transform
  approach (e.g. `puts "hello \u21a9 there"` displayed as several wrong
  characters instead of one). The transform now decodes using the
  channel's actual configured encoding before handing data to the console
  widget, rather than passing the raw encoded bytes straight through.

Reference implementation:
[consolecmd.tcl](https://github.com/rocketship88/tcl-console-unix/blob/main/consolecmd.tcl)
and
[consolecmd.impl](https://github.com/rocketship88/tcl-console-unix/blob/main/consolecmd.impl).

# A Note on `console eval` as a Semi-Public Interface

Beyond simply opening a console window, `console eval` gives a script direct access to the
console's own widgets and to the main interpreter. This is already used in
real, long-standing code - for example, colorized output via
`::tk::ConsoleOutput` with custom tags (note: stdout and stderr are
themselves implemented as text tags), or adding extra menu
items and buttons to the console window itself (see
[the Tcler's Wiki](https://wiki.tcl-lang.org/page/console) for examples in
active use for close to 20 years).

None of this is documented as a stable interface today. The manual page
itself lists `tk::ConsoleOutput` under a section titled "Additional Trap
Calls"

As part of making `console` an officially supported command on Unix, it would
be worth the core team also considering `tk::ConsoleOutput` and the small
set of related internals it documents as a semi-public interface worth
keeping stable going forward, given how much existing code already quietly
depends on it.

As one small example of what this already enables: undo/redo can be added to
the console with nothing more than

```tcl
console eval {
    .console configure -undo 1
    bind Console <Control-z> {%W edit undo}
    bind Console <Control-y> {%W edit redo}
}
```

with no core changes required at all - a documentation-only addition, offered
here simply as evidence of how much is already possible through this
interface as it stands today.

# Future Work

One case is not addressed by this proposal: a `wish` process started with no
script argument and no real controlling terminal attached - for example,
launched by double-clicking `wish` itself from a desktop file manager. On
Windows, this case automatically opens a console. This proposal does not
attempt to replicate that behavior on Unix, and leaves it as a follow-up
item for future consideration.

# Copyright

This document has been placed in the public domain.
