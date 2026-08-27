# consolemonitor_addon.tcl
#
# This file uses fetch1 and fetch3, defined in consoleclient1.tcl
# and consoleclient3.tcl - both are sourced automatically, so the
# code assumes all three files are in the same directory. Then this
# file can be double clicked in Windows or, use this from the
# command line
#
#   wish /pathto/consolemonitor_addon.tcl
#
# To set the DEFAULT ip address, see the lines at the bottom and
# set ipvar to your choice. Once running, and ip is set, click
# the monitoring checkbox to start. To pause, uncheck it.
#
# Check "plain text only" to fetch plain, uncolored text via fetch1
# instead of the full tagged/colorized dump via fetch3. Toggling
# this always pauses monitoring - check monitoring again afterward
# to resume with the new setting.
#
# The "update secs" spinbox sets how often (in seconds) the console
# is checked for changes; it can be changed at any time, including
# while monitoring is running.
#

# --- monitor GUI --------------------------------------------------
# Builds the control panel described above and drives the polling
# loop: each cycle, asks consolesrv2 (port 9997) for the .console
# insert index, and if it's changed, fetches the console's contents
# via fetch1 (consolesrv1, port 9998) or fetch3 (consolesrv3, port
# 9996) depending on the "plain text only" checkbox.

proc wait { ms } {
    set uniq [incr ::__sleep__tmp__counter]
    set ::__sleep__tmp__$uniq 0
    after $ms set ::__sleep__tmp__$uniq 1
    vwait ::__sleep__tmp__$uniq
    unset ::__sleep__tmp__$uniq
}

namespace eval ::monitor {
    variable evalsock         ""   ;# persistent connection to consolesrv2
    variable lastinsert       ""   ;# last-seen signature (see SignatureCmd)
    variable firstpass        1    ;# have we connected yet this monitoring run?
    variable running          1    ;# controls the polling loop
    variable monvar           0    ;# backing variable for the monitoring checkbutton
    variable forcefetch       0    ;# force next poll to fetch regardless of change
    variable plaintextvar     0    ;# backing variable for the "plain text only" checkbutton
    variable updatesecs       1    ;# backing variable for the update-interval spinbox
    variable signatureCmdCache      ;# cached command text, computed on first use by SignatureCmd
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

# Called when the "plain text only" checkbutton is clicked. Changing
# this setting mid-monitoring would mix fetch1/fetch3 results in a
# confusing way, so turn monitoring off whenever it changes - the
# user can turn monitoring back on afterward, which will pick up
# the new setting cleanly on the next connect.
proc ::monitor::PlainTextToggled {} {
    variable monvar
    variable forcefetch
    set monvar 0
    set forcefetch 0
}

proc ::monitor::EvalPort  {} { return 9997 }
proc ::monitor::DumpPort  {} { return 9996 }
proc ::monitor::PlainPort {} { return 9998 }

# The single console eval command used to detect whether anything
# has changed. Returns a 3-element list: insert index, total char
# count, and a simple hash+length signature of line 1's content.
# Using several signals together, rather than insert index alone,
# avoids false negatives after ::tk::console::ConstrainBuffer trims
# old lines from the top - trimming can coincidentally leave the
# insert index unchanged, but is very unlikely to leave all these
# signals unchanged at once. (An equivalent signal for the last
# line was tried too, but dropped - it's usually just an empty
# line between commands, so it added little discriminating power.)
#
# The hash itself is a simple polynomial rolling hash (multiply by
# a prime, add each character's code, modulo a large prime) - not
# cryptographic, just cheap and well-distributed enough to catch an
# actual content change. Computed inline via [apply], so nothing is
# left defined in the remote interpreter between polls - no external
# package (tcllib, zlib, etc.) is required either.
proc ::monitor::SignatureCmd {} {
    variable signatureCmdCache
    if {[info exists signatureCmdCache]} {
        return $signatureCmdCache
    }
    set hashLambda {{str} {
        set h 0
        foreach c [split $str ""] {
            set h [expr {($h * 131 + [scan $c %c]) % 4294967291}]
        }
        return "[string length $str]:$h"
    }}
    set signatureCmdCache [format {console eval {list \
        [.console index insert] \
        [.console count -chars 1.0 end] \
        [apply {%s} [.console get 1.0 1.end]] \
    }} $hashLambda]
    return $signatureCmdCache
}

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
        set lastinsert [::monitor::EvalRemote [::monitor::SignatureCmd]]
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
    variable plaintextvar
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
        set current [::monitor::EvalRemote [::monitor::SignatureCmd]]
    } err]} {
        puts stderr "monitor: eval connection lost - $err"
        ::monitor::Disconnect
        set firstpass 1
        return
    }

    if {$current ne $lastinsert || $forcefetch} {
        set forcefetch 0
        set lastinsert $current
        if {$plaintextvar} {
            if {[catch {fetch1 $ip [::monitor::PlainPort]} err]} {
                puts stderr "monitor: fetch1 failed - $err"
            }
        } else {
            if {[catch {fetch3 $ip [::monitor::DumpPort]} err]} {
                puts stderr "monitor: fetch3 failed - $err"
            }
        }
    }
}

proc ::monitor::Loop {} {
    variable running
    variable updatesecs
    while {$running} {
        ::monitor::Poll
        wait [expr {round($updatesecs * 1000)}]
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
    wm geometry .monitorgui 400x180+1+1

    label  .monitorgui.iplabel -text "IP address:"
    entry  .monitorgui.ipentry -width 20 -textvariable ::ipvar
    button .monitorgui.copybtn -text "Copy" -command ::monitor::CopyIP

    checkbutton .monitorgui.mon -text "monitoring" -variable ::monitor::monvar \
        -command ::monitor::MonitorToggled

    checkbutton .monitorgui.plaintext -text "plain text only" \
        -variable ::monitor::plaintextvar -command ::monitor::PlainTextToggled

    label .monitorgui.updatelabel -text "update secs:"
    spinbox .monitorgui.updatespin -width 5 \
        -values {1 1.5 2 2.5 3 3.5 4 4.5 5} \
        -textvariable ::monitor::updatesecs -state readonly

    # Mousewheel support: Windows/Mac report scroll via <MouseWheel>
    # with a %D delta; Linux/X11 traditionally reports scroll as
    # Button-4 (up) / Button-5 (down) clicks instead, with no delta.
    bind .monitorgui.updatespin <MouseWheel> {
        .monitorgui.updatespin invoke [expr {%D > 0 ? "buttonup" : "buttondown"}]
    }
    bind .monitorgui.updatespin <Button-4> {
        .monitorgui.updatespin invoke buttonup
    }
    bind .monitorgui.updatespin <Button-5> {
        .monitorgui.updatespin invoke buttondown
    }

    label .monitorgui.portnote -text "use port 9997 in tkcon"

    button .monitorgui.clearbtn -text "Clear Remote" -command ::monitor::ClearRemote

    button .monitorgui.exitbtn -text "Exit" -command ::monitor::ExitProgram

    grid .monitorgui.iplabel -row 0 -column 0 -sticky w -padx 4 -pady 4
    grid .monitorgui.ipentry -row 0 -column 1 -sticky ew -padx 4 -pady 4
    grid .monitorgui.copybtn -row 0 -column 2 -padx 4 -pady 4
    grid .monitorgui.mon      -row 1 -column 0 -sticky w -padx 4 -pady 4
    grid .monitorgui.plaintext -row 1 -column 1 -sticky w -padx 4 -pady 4
    grid .monitorgui.exitbtn  -row 1 -column 2 -padx 4 -pady 4
    grid .monitorgui.updatelabel -row 2 -column 0 -sticky w -padx 4 -pady 4
    grid .monitorgui.updatespin  -row 2 -column 1 -sticky w -padx 4 -pady 4
    grid .monitorgui.clearbtn -row 3 -column 2 -padx 4 -pady 4
    grid .monitorgui.portnote -row 3 -column 0 -columnspan 2 -sticky w -padx 4 -pady 4

    grid columnconfigure .monitorgui 1 -weight 1

    wm protocol .monitorgui WM_DELETE_WINDOW ::monitor::ExitProgram
}

# use this script to start mirror
#
if {yes} {
    set ipvar "192.168.118.130" ;# default ip address for text entry
    console show

    foreach client {consoleclient1.tcl consoleclient3.tcl} {
        if { [file exist [set temp [file join [file dir [info script]] $client]]] }  {
            source $temp
        } else {
            puts stderr "cannot find source $temp\nMust be in the same directory with this file: [info script]"
        }
    }
}
::monitor::BuildGUI
::monitor::Loop
