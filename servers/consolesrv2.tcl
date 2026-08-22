# consolesrv2.tcl - persistent multi-connection remote-eval server
# for use with tkcon's socket attach (Host:/Port: dialog), port 9997.
#
# Protocol matches what tkcon's EvalSocket/EvalSocketEvent expect:
# tkcon writes a line (a Tcl command), we read it, eval it in the
# main interpreter, and write one line back with the result (or the
# error message, prefixed).
#
# Unlike consolesrv1/consolesrv3 (one-shot dump-and-close), this
# server:
#   - accepts MULTIPLE simultaneous connections, each with its own
#     independent read/eval/reply loop
#   - stays open across many commands per connection, rather than
#     closing after one reply
#   - closes a connection only when the client sends the literal
#     command "done", or disconnects on its own (EOF)
#
# SECURITY NOTE: this evaluates arbitrary Tcl sent over the socket,
# with no authentication at all. Anyone who can reach this port can
# run arbitrary code in this process. Only bind/expose this on a
# trusted network (localhost, an SSH tunnel, or an isolated
# container network) - never expose it on an open/public port as-is.
#
# Usage: source this into your running wish app. Then, from tkcon:
#   File -> New Socket / Attach -> host = <this machine>, port 9997

namespace eval ::consolesrv2 {
    variable listener
    variable conns
    variable buffers
    variable timeoutid
    array set conns {}
    array set buffers {}
    array set timeoutid {}
}

proc ::consolesrv2::PasteTimeoutMs {} { return 2000 }

proc ::consolesrv2::Accept {chan addr port} {
    variable conns
    fconfigure $chan -translation binary -encoding utf-8 \
        -buffering line -blocking 0
    set conns($chan) [list $addr $port]
    puts stderr "consolesrv2: connection from $addr:$port ($chan)"
    fileevent $chan readable [list ::consolesrv2::HandleLine $chan]
}

proc ::consolesrv2::HandleLine {chan} {
    variable conns
    variable buffers
    variable timeoutid

    if {[eof $chan]} {
        ::consolesrv2::CancelTimeout $chan
        ::consolesrv2::CloseConn $chan
        return
    }

    if {[gets $chan line] < 0} {
        # no complete line yet (non-blocking partial read); wait
        # for the next readable event
        return
    }

    # a line arrived - cancel any pending paste-timeout, we'll
    # re-arm one below only if we're still incomplete after this
    ::consolesrv2::CancelTimeout $chan

    # accumulate this line onto whatever's already buffered for
    # this connection (handles multi-line pastes, e.g. a proc body)
    if {[info exists buffers($chan)]} {
        append buffers($chan) "\n" $line
    } else {
        set buffers($chan) $line
    }

    set trimmed [string trim $buffers($chan)]

    if {$trimmed eq "done"} {
        catch {puts $chan "closing"}
        catch {flush $chan}
        unset -nocomplain buffers($chan)
        ::consolesrv2::CloseConn $chan
        return
    }

    if {$trimmed eq ""} {
        # blank line(s) only - reset and wait for real input
        unset -nocomplain buffers($chan)
        return
    }

    if {![info complete $buffers($chan)]} {
        # not a complete command yet (e.g. mid-proc-body) - keep
        # buffering, but arm a timeout in case the rest never
        # arrives (e.g. someone typed an unclosed brace manually
        # rather than pasting a complete block)
        set timeoutid($chan) [after [::consolesrv2::PasteTimeoutMs] \
            [list ::consolesrv2::PasteTimeout $chan]]
        return
    }

    set cmd $buffers($chan)
    unset -nocomplain buffers($chan)

    if {[catch {uplevel #0 $cmd} result]} {
        catch {puts $chan "ERROR: $result"}
    } else {
        catch {puts $chan $result}
    }
    catch {flush $chan}
}

proc ::consolesrv2::CancelTimeout {chan} {
    variable timeoutid
    if {[info exists timeoutid($chan)]} {
        catch {after cancel $timeoutid($chan)}
        unset -nocomplain timeoutid($chan)
    }
}

proc ::consolesrv2::PasteTimeout {chan} {
    variable buffers
    variable timeoutid
    unset -nocomplain timeoutid($chan)
    if {[info exists buffers($chan)]} {
        catch {
            puts $chan "ERROR: incomplete command, timed out waiting for more input (paste it as one block)"
            flush $chan
        }
        unset -nocomplain buffers($chan)
    }
}

proc ::consolesrv2::CloseConn {chan} {
    variable conns
    variable buffers
    if {[info exists conns($chan)]} {
        puts stderr "consolesrv2: disconnect [lindex $conns($chan) 0]:[lindex $conns($chan) 1] ($chan)"
    }
    ::consolesrv2::CancelTimeout $chan
    catch {fileevent $chan readable {}}
    catch {close $chan}
    unset -nocomplain conns($chan)
    unset -nocomplain buffers($chan)
}

proc ::consolesrv2::Start {{port 9997}} {
    variable listener
    set listener [socket -server ::consolesrv2::Accept $port]
    puts "consolesrv2: listening on port $port (multi-connection, eval loop)"
    return $listener
}

proc ::consolesrv2::Stop {} {
    variable listener
    variable conns
    foreach chan [array names conns] {
        ::consolesrv2::CloseConn $chan
    }
    catch {close $listener}
}

proc ::consolesrv2::ListConns {} {
    variable conns
    foreach chan [array names conns] {
        puts "$chan -> [lindex $conns($chan) 0]:[lindex $conns($chan) 1]"
    }
}

::consolesrv2::Start 9997
