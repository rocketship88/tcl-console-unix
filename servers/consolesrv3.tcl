# consolesrv3.tcl - console-dump server, WITH tag info (port 9996)
#
# Same idea as earlier try, but normalizes each dump element
# through [list] before sending, so every element gets Tcl's own
# consistent, safe quoting - avoiding the mixed brace/backslash
# quoting styles that [.console dump] itself produces, which don't
# reliably survive further string rewriting (tocode/subst) as one
# flat list.
#
# Usage: source this into your running wish app. Then use the
# companion client (consoleclient3.tcl, fetch3 proc) pointed at
# port 9996.

namespace eval ::consolesrv3 {}

namespace eval ::consolesrv3 {
    variable conv
    unset -nocomplain conv
}

proc ::consolesrv3::tocode {str} { ;# revert back to unicode \uFFFF so can be placed in source code
    variable conv
    if { ![info exist conv] } {
        set conv [list "\t" "\\t" " " " "] ;# space to space for speedup, same as letter/symbols below
        set c {e i a n s o r t l c u d p m h g y b f v k w z x j q E I A N S O R T L C U D P M H G Y B F V K W Z X J Q 0 1 2 3 4 5 6 7 8 9 0}
        set d {! @ # $ % ^ & * ( ) _ + - = [ ] ; ' : < > , . / ?}
        foreach letter [concat {{ }} $c $d] {
            lappend conv $letter $letter
        }
        # Curly braces, double quotes, and backslash are list and
        # subst structural characters. subst's fallback rule for an
        # unrecognized backslash sequence is to drop the backslash
        # and keep the next char literal - which would turn a safely
        # escaped open-brace sequence back into a live, list-breaking
        # brace. Route these through \uXXXX instead, which subst DOES
        # correctly recognize and convert back to the real character.
        lappend conv "\{" "\\u007b" "\}" "\\u007d" "\"" "\\u0022" "\\" "\\u005c"
        # most chars are not unicode, so the above is found quickly worst case is no hit at all
        for {set m 0x100} {$m < 0xffff} {incr m} {
            if { $m == 0x2424 || $m == 0x2409} {
                continue ;# except for our nl char or horizontal tab
            }
            set h [format %04x $m  ]
            set y "set x \\u$h"
            eval $y
            lappend conv $x "\\u$h"
        }
    }
    return [string map $conv $str]
}

# Normalize a raw [dump] result into a re-listed form: walk it as a
# real list (llength/lindex, immune to its original mixed quoting),
# then rebuild with [list key value index ...] so every element gets
# one consistent, safe, guaranteed-round-trippable quoting style.
proc ::consolesrv3::normalize {rawdump} {
    set n [llength $rawdump]
    set out {}
    for {set i 0} {$i < $n} {incr i 3} {
        set key   [lindex $rawdump $i]
        set value [lindex $rawdump [expr {$i + 1}]]
        set index [lindex $rawdump [expr {$i + 2}]]
        lappend out $key $value $index
    }
    return $out
}

proc ::consolesrv3::Accept {chan addr port} {
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

    if {[catch {console eval {.console dump -all 1.0 end}} rawdata]} {
        puts $chan "ERROR: could not read console: $rawdata"
        flush $chan
        close $chan
        return
    }

    # Re-list the dump so every element has consistent, safe quoting
    # BEFORE it ever gets run through tocode/subst.
    set data [normalize $rawdata]

    # Gather tag definitions: for each tag name, its configure options.
    if {[catch {
        set tagdefs {}
        foreach tname [console eval {.console tag names}] {
            set opts [console eval [list .console tag configure $tname]]
            set flat {}
            foreach o $opts {
                lassign $o optname dbname dbclass default current
                if {$current ne ""} {
                    lappend flat $optname $current
                }
            }
            lappend tagdefs $tname $flat
        }
    } terr]} {
        set tagdefs {}
    }

    # Escape to \uXXXX / 7-bit-safe form so it survives the socket
    # transport and framing markers intact.
    set data [tocode $data]
    set tagdefs [tocode $tagdefs]

    puts $chan "TAGDEFS"
    puts $chan $tagdefs
    puts $chan "DUMP"
    puts -nonewline $chan $data
    puts $chan ""
    puts $chan "ENDDUMP"
    flush $chan
    close $chan
}

proc ::consolesrv3::Start {{port 9996}} {
    variable listener
    set listener [socket -server ::consolesrv3::Accept $port]
    puts "consolesrv3: listening on port $port"
    return $listener
}

proc ::consolesrv3::Stop {} {
    variable listener
    catch {close $listener}
}

::consolesrv3::Start 9996
