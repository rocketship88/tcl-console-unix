# consolemonitor_addon.tcl
#
# This file uses fetch3, which is defined in consoleclient3.tcl - so
# that file must be sourced first (or this file appended directly to
# the end of it). To use as a separate file:
#
#   source /pathto/consoleclient3.tcl
#   source /pathto/consolemonitor_addon.tcl
#
# To preload a default IP address into the entry field, set the
# global "ipvar" to the desired value just BEFORE sourcing this
# file, a complete small setup script would be:
#
#   console show
#   source /pathto/consoleclient3.tcl
#   set ipvar "192.168.118.130"
#   source /pathto/consolemonitor_addon.tcl
#
# Note: this file ends by entering its own polling loop (via the
# "wait" proc), so nothing placed after the "source" line in the
# calling script will run until the monitor's Exit button is used.

# --- monitor GUI --------------------------------------------------
# Appends a small control panel: IP entry, copy-to-clipboard button,
# a "monitoring" checkbox, and an Exit button. While monitoring is
# on, once a second it asks the tkcon-style eval server (consolesrv2,
# port 9997) for the .console insert index. If that index has
# changed since the last check, it calls fetch3 (consolesrv3, port
# 9996) to pull and reconstruct the full tagged dump.

proc wait { ms } {
    set uniq [incr ::__sleep__tmp__counter]
    set ::__sleep__tmp__$uniq 0
    after $ms set ::__sleep__tmp__$uniq 1
    vwait ::__sleep__tmp__$uniq
    unset ::__sleep__tmp__$uniq
}

namespace eval ::monitor {
    variable evalsock   ""   ;# persistent connection to consolesrv2
    variable lastinsert ""   ;# last-seen .console insert index
    variable firstpass  1    ;# have we connected yet this monitoring run?
    variable running    1    ;# controls the polling loop
    variable monvar     0    ;# backing variable for the monitoring checkbutton
    variable forcefetch 0    ;# force next poll to fetch regardless of change
}

# ipvar is a plain GLOBAL, not namespaced, so the outer script can
# set it before sourcing this file to preload a default IP, e.g.:
#   set ipvar "192.168.118.130"
#   source consolemonitor_addon.tcl
if {![info exists ::ipvar]} {
    set ::ipvar ""
}

# Called when the monitoring checkbutton is clicked. When turned on,
# force the very next poll to download rather than waiting for the
# insert index to actually differ from whatever it was last time.
proc ::monitor::MonitorToggled {} {
    variable monvar
    variable forcefetch
    if {$monvar} {
        set forcefetch 1
    }
}

proc ::monitor::EvalPort  {} { return 9997 }
proc ::monitor::DumpPort  {} { return 9996 }

# Send one line to the persistent eval socket, read one line back.
proc ::monitor::EvalRemote {cmd} {
    variable evalsock
    puts $evalsock $cmd
    flush $evalsock
    set result [gets $evalsock]
    return $result
}

proc ::monitor::Connect {ip} {
    variable evalsock
    variable firstpass
    variable lastinsert
    set evalsock [socket $ip [::monitor::EvalPort]]
    fconfigure $evalsock -translation binary -encoding utf-8 -blocking 1
    set firstpass 0
    # prime lastinsert so the very first poll after connecting
    # doesn't necessarily trigger a fetch unless something's
    # actually different from here on
    catch {
        set lastinsert [::monitor::EvalRemote {console eval {.console index insert}}]
    }
}

proc ::monitor::Disconnect {} {
    variable evalsock
    if {$evalsock ne ""} {
        catch {puts $evalsock "done"; flush $evalsock}
        catch {close $evalsock}
        set evalsock ""
    }
}

proc ::monitor::Poll {} {
    variable evalsock
    variable firstpass
    variable lastinsert
    variable monvar
    variable forcefetch
    global ipvar

    if {![winfo exists .monitorgui.mon] || !$monvar} {
        # monitoring checkbox is off - do nothing, but make sure
        # we're disconnected so we reconnect cleanly if re-enabled
        if {$evalsock ne ""} {
            ::monitor::Disconnect
        }
        set firstpass 1
        return
    }

    set ip [string trim $ipvar]
    # (ipvar is the plain global, brought into scope above via 'global ipvar')
    if {$ip eq ""} {
        return
    }

    if {$firstpass} {
        if {[catch {::monitor::Connect $ip} err]} {
            puts stderr "monitor: could not connect to $ip:[::monitor::EvalPort] - $err"
            set monvar 0
            return
        }
    }

    if {[catch {
        set current [::monitor::EvalRemote {console eval {.console index insert}}]
    } err]} {
        puts stderr "monitor: eval connection lost - $err"
        ::monitor::Disconnect
        set firstpass 1
        return
    }

    if {$current ne $lastinsert || $forcefetch} {
        set forcefetch 0
        set lastinsert $current
        if {[catch {fetch3 $ip [::monitor::DumpPort]} err]} {
            puts stderr "monitor: fetch3 failed - $err"
        }
    }
}

proc ::monitor::Loop {} {
    variable running
    while {$running} {
        ::monitor::Poll
        wait 1000
    }
    ::monitor::Disconnect
}

proc ::monitor::ClearRemote {} {
    variable evalsock
    if {$evalsock eq ""} {
        puts stderr "monitor: not connected - enable monitoring first"
        return
    }
    if {[catch {
        ::monitor::EvalRemote {console eval {.console delete 1.0 end}}
    } err]} {
        puts stderr "monitor: clear failed - $err"
    }
}

proc ::monitor::CopyIP {} {
    global ipvar
    clipboard clear
    clipboard append $ipvar
}

proc ::monitor::ExitProgram {} {
    variable running
    set running 0
    ::monitor::Disconnect
    exit
}

proc ::monitor::BuildGUI {} {
    wm withdraw .

    toplevel .monitorgui
    wm title .monitorgui "Console Monitor"
    wm geometry .monitorgui 400x150+1+1

    label  .monitorgui.iplabel -text "IP address:"
    entry  .monitorgui.ipentry -width 20 -textvariable ::ipvar
    button .monitorgui.copybtn -text "Copy" -command ::monitor::CopyIP

    checkbutton .monitorgui.mon -text "monitoring" -variable ::monitor::monvar \
        -command ::monitor::MonitorToggled

    label .monitorgui.portnote -text "use port 9997 in tkcon"

    button .monitorgui.clearbtn -text "Clear Remote" -command ::monitor::ClearRemote

    button .monitorgui.exitbtn -text "Exit" -command ::monitor::ExitProgram

    grid .monitorgui.iplabel -row 0 -column 0 -sticky w -padx 4 -pady 4
    grid .monitorgui.ipentry -row 0 -column 1 -sticky ew -padx 4 -pady 4
    grid .monitorgui.copybtn -row 0 -column 2 -padx 4 -pady 4
    grid .monitorgui.mon     -row 1 -column 0 -columnspan 2 -sticky w -padx 4 -pady 4
    grid .monitorgui.exitbtn -row 1 -column 2 -padx 4 -pady 4
    grid .monitorgui.clearbtn -row 2 -column 2 -padx 4 -pady 4
    grid .monitorgui.portnote -row 2 -column 0 -columnspan 2 -sticky w -padx 4 -pady 4

    grid columnconfigure .monitorgui 1 -weight 1

    wm protocol .monitorgui WM_DELETE_WINDOW ::monitor::ExitProgram
}

::monitor::BuildGUI
::monitor::Loop
