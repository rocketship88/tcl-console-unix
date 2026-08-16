# consoleclient1.tcl - fetch a remote console's plain text buffer
# (no tags/formatting) and drop it into the local console.
#
# Usage (from a plain wish, with "console show" already run once
# so .console exists locally):
#   source consoleclient1.tcl
#   fetch1 <ip> 9998

proc fetch1 {ip {port 9998}} {
    global data1

    set sock [socket $ip $port]
    fconfigure $sock -translation binary -encoding utf-8 -blocking 1
    set data1 [read $sock]
    close $sock
    set data1 [string trimright $data1 \n]

    if {[string match "ERROR:*" $data1]} {
        puts "fetch1: $data1"
        return
    }

    console show
    update

    console eval {.console delete 1.0 end}
    console eval [list .console insert end $data1]
    console eval [list .console insert end \
        "\n--- remote dump from $ip:$port ---\n" ]
    console eval {.console see end}

    puts "fetch1: done, [string length $data1] bytes"
}
history add {fetch1 192.168.118.130 9998}
console show
