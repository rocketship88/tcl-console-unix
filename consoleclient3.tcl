# consoleclient3.tcl - fetches a remote console's tagged dump and
# reconstruct it into the local console's .console text widget.
#
# Usage (from a plain wish, with "console show" already run once
# so .console exists locally):
#   source consoleclient3.tcl
#   fetch3 <ip> 9996
#------------------------------------

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
history add {fetch3 192.168.118.130 9996}
console show

