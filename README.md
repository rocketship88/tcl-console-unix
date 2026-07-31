# TIP 561: Console Command for Linux/Unix

This repository contains the **working console implementation** for TIP 561, which proposes adding official support for the `console` command on Linux and other Unix platforms.

Note: the new TIP will use the files consolecmd.tcl and consolecmd.impl whereas an earlier version that was using a module and a stub are no longer being considered. Those files will remain for reference only.

## Overview

Currently, the console command works "out of the box" on Windows and macOS, but requires additional code on Linux/Unix. This TIP proposes making console support a standard feature across all Tk-enabled platforms.

## About This File

This `consolecmd.impl` file is the **core implementation** that provides the console functionality once activated. 

**Important:** The full TIP 561 proposal delays initialization of this console until a user explicitly issues a console command (like `console show`). This ensures backward compatibility - Unix/Linux users who don't want the console will see no behavior change, with stdout/stderr continuing to go to the terminal as before.

See the [TIP 561 document](https://core.tcl-lang.org/tips/doc/trunk/tip/561.md)for the complete wrapper implementation that provides this lazy initialization behavior.

## Key Improvements in This Implementation

### 1. Working Channel Transform Support (Tcl 8.6+)

The primary enhancement is a properly functioning channel transform implementation that correctly handles Unicode output.

**The Problem:** Previous channel transform attempts failed to display Unicode characters correctly. For example:
```tcl
puts "hello \u21a9 there"
# Would display: hello â© there  (incorrect)
# Should display: hello ↩ there  (correct)
```

**The Solution:** Channel transforms receive UTF-8 encoded bytes from stdout/stderr, but the Tk console widget expects Unicode strings. The fix decodes the bytes before passing them to the console:

```tcl
proc write {what x data} {
    set data [encoding convertfrom utf-8 $data]
    set data [string map {\r ""} $data]
    $consoleInterp eval [list ::tk::ConsoleOutput $what $data]
    return ""
}
```

This approach eliminates the need for the pre-8.6 `puts` wrapper method, which required renaming and redefining the `puts` command.

### 2. Proper Console Cleanup and Output Restoration

When the console window is closed, output is now correctly restored to the terminal:

- Uses `wm protocol . WM_DELETE_WINDOW` instead of `bind <Destroy>` to catch the close event early
- Properly pops channel transforms and restores terminal encoding
- Insures that multiple console show commands only push/pop one transform
- Restores stdin/stdout properly when console is closed or console hide is used.

### 3. Improved Keyboard Shortcuts

Added platform-consistent font size controls:
- `Control+=` (unshifted) in addition to `Control++`
- Keypad `Control+KP_Add` and `Control+KP_Subtract`
- Unix style middle click operation is supported but on Unix only


## Usage

For testing purposes, you can source this file directly:

```tcl
source consolecmd.impl
console show
```

In the final TIP 561 implementation, the wrapper code ensures the console is only initialized when explicitly requested by the user. In the tclIndex implementation, this is handled by that lazy loading implemenation, rather than new code to do the same thing.

## Benefits

1. **Platform Consistency**: Eliminates the incompatibility between Windows/macOS and Linux/Unix
2. **Clean Implementation**: Uses official channel transform API instead of command renaming hacks
3. **Unicode Support**: Properly handles international characters and symbols
4. **Future-Proof**: Uses documented APIs that won't break in future Tcl releases
5. **Backward Compatible**: Existing Unix/Linux behavior unchanged unless console is explicitly invoked

## Related Links

- [TIP 561 Proposal](https://core.tcl-lang.org/tips/doc/trunk/tip/561.md) (if available)
- [Original Tcl'ers Wiki Code](https://wiki.tcl-lang.org/page/console)

## Testing

Tested on:
- Pop!_OS Linux (Ubuntu-based)
- Tcl/Tk 8.6+

The implementation should work on any Unix-like system with Tcl/Tk 8.6 or later.
