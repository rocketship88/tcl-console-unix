# consolesrv1.tcl - minimal single-shot console-dump server (plain text)
#
# Listens on port 9998. On each connection: checks whether the
# console command is available; if so, grabs the current console
# text buffer as plain text (no tags/formatting) and sends it back;
# if not, sends a short error message. Either way, closes the
# socket right after sending.
#
# Usage: source this into your running wish app. Then use the
# companion client (consoleclient1.tcl, fetch1 proc).

namespace eval ::consolesrv1 {}

proc ::consolesrv1::Accept {chan addr port} {
    fconfigure $chan -translation binary -encoding utf-8 -buffering full

    if {[info commands console] eq ""} {
        puts $chan "ERROR: no console available"
        flush $chan
        close $chan
        return
    }

    if {[catch {console eval {winfo exists .console}} exists] || !$exists} {
        puts $chan "ERROR: no console available"
        flush $chan
        close $chan
        return
    }

    if {[catch {console eval {.console get 1.0 end}} data]} {
        puts $chan "ERROR: could not read console: $data"
        flush $chan
        close $chan
        return
    }

    puts -nonewline $chan $data
    flush $chan
    close $chan
}

proc ::consolesrv1::Start {{port 9998}} {
    variable listener
    set listener [socket -server ::consolesrv1::Accept $port]
    puts "consolesrv1: listening on port $port"
    return $listener
}

proc ::consolesrv1::Stop {} {
    variable listener
    catch {close $listener}
}

::consolesrv1::Start 9998
