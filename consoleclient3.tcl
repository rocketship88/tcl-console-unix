# consoleclient3.tcl - fetches a remote console's tagged dump and
# reconstruct it into the local console's .console text widget.
#
# Usage (from a plain wish, with "console show" already run once
# so .console exists locally):
#   source consoleclient3.tcl
#   fetch3 <ip> 9996
#
# Also provides sendproc, a workaround for tkcon's socket-attach
# mode mangling backslashes (tkcon's EvalSocket runs every command
# through [subst -novariables -nocommands] before sending, which
# corrupts things like \d, \d+, or a literal \\ in pasted code -
# see consolesrv2.tcl's header for details). To use: paste/type the
# proc you want to send into THIS console (the local one, not via
# tkcon), then call:
#   sendproc <procname> <ip> [port 9997]
# This reconstructs the proc's real definition locally via [info
# args]/[info body]/[info default] and sends it as one single,
# untouched write to consolesrv2's eval socket - no subst involved
# anywhere in this path, so backslashes arrive exactly as typed.

proc reconstruct {proc_name} {
    set proc_name [uplevel 1 [list namespace which -command $proc_name]]
    set params [lmap param_name [info args $proc_name] {
        if {[info default $proc_name $param_name defval]} {
            list $param_name $defval
        } else {
            list $param_name
        }
    }]
    return [list proc $proc_name $params [info body $proc_name]]
}

proc sendproc {procname {ip ""} {port 9997}} {
    global ipvar
    if { $ip eq "" } {
    	catch {set ip $ipvar}
    }
    if {[catch {uplevel 1 [list reconstruct $procname]} fulltext]} {
        puts "sendproc: no such proc \"$procname\" defined locally"
        return
    }

    set sock [socket $ip $port]
    fconfigure $sock -translation binary -encoding utf-8 -blocking 1
    puts $sock $fulltext
    flush $sock

    # read back whatever consolesrv2 replies with for this command
    set result [gets $sock]
    puts $sock "done"
    flush $sock
    catch {gets $sock} ;# consume the "closing" reply, if any
    close $sock

    puts "sendproc: sent $procname to $ip:$port -> $result"
}

proc fetch3 {ip {port 9996}} {
    global data tagdefs
    
    set sock [socket $ip $port]
    fconfigure $sock -translation binary -encoding utf-8 -blocking 1

    set line1 [gets $sock]
    if {[string match "ERROR:*" $line1]} {
        close $sock
        puts "fetch3: $line1"
        return
    }
    if {$line1 ne "TAGDEFS"} {
        close $sock
        puts "fetch3: unexpected response (no TAGDEFS marker)"
        return
    }

    set tagdefs [gets $sock]

    set marker [gets $sock]
    if {$marker ne "DUMP"} {
        close $sock
        puts "fetch3: unexpected response (no DUMP marker)"
        return
    }

    # Read everything up to the ENDDUMP marker line. The dump text
    # itself may contain embedded newlines (from puts'd lines in the
    # original console), so we can't just [gets] once - read the
    # rest of the stream and split off the trailing marker.
    set rest [read $sock]
    close $sock

    set endpos [string last "\nENDDUMP" $rest]
    if {$endpos == -1} {
        puts "fetch3: unexpected response (no ENDDUMP marker)"
        return
    }
    set data [string range $rest 0 [expr {$endpos - 1}]]
    set tagdefs [subst -nocommands -novariables $tagdefs]

    # Make sure our own console exists
    console show
    update

    # Clear it
    console eval {.console delete 1.0 end}

    # Apply tag definitions first, so text inserted with these tags
    # picks up the right colors/fonts immediately.
    foreach {tname topts} $tagdefs {
        if {[llength $topts]} {
            catch {console eval [list .console tag configure $tname {*}$topts]}
        }
    }

    # restore must run INSIDE the console interp, since .console
    # only exists there. Define it there once, then call it there
    # too, passing the (still-escaped) data across as a single
    # list argument - console eval takes care of quoting it safely.
    console eval {
        proc ::restore {w savex} {
            set save [subst -nocommands -novariables $savex]
            set n [llength $save]
            for {set i 0} {$i < $n} {incr i 3} {
                set key   [lindex $save $i]
                set value [lindex $save [expr {$i + 1}]]
                set index [lindex $save [expr {$i + 2}]]
                switch $key {
                    exec    { eval [string replace $value 0 [string first " " $value]-1 $w] }
                    image   { $w image create $index -name $value }
                    text    { $w insert $index $value }
                    mark    {
                        switch $value {
                            current { set ::currentIndex $index }
                            insert { set ::insertIndex $index }
                            default { $w mark set $value $index }
                        }
                    }
                    tagon   { set ::tag($value) $index }
                    tagoff  { $w tag add $value $::tag($value) $index }
                    window  { $w window create $index -window $value }
                }
            }
            catch {$w mark set current $::currentIndex}
            catch {$w mark set insert $::insertIndex}
        }
    }
    console eval [list ::restore .console $data]

    console eval [list .console insert end \
        "\n--- remote dump from $ip:$port ---\n" ]
    console eval {.console see end}
    puts "fetch3: done, [string length $data] bytes processed"
}
history add {fetch3 192.168.118.130 9996 ;  console eval {after 200 {tk::ConsoleHistory prev ; focus .console}}}
history add {fetch3 127.0.0.1 9996  ;  console eval {after 200 {tk::ConsoleHistory prev; focus .console}}}
console show

set ipvar "192.168.118.130"
source {D:/podcasts/console servers and clients/consolemonitor_addon.tcl}
