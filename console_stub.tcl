# FILE: console_stub.tcl
#
# Installs a lightweight placeholder "console" command. On first real
# use, it transparently loads console-1.0.tm (via "package require
# console") and forwards the original call to it. On platforms where
# console already exists as a native command (Windows/Mac), this does
# nothing at all - see the guard at the top of console-1.0.tm.
#
# This file is intended to be sourced automatically at Tk startup;
# or more likely, inserted into the tk init code somewhere.
# console-1.0.tm should be installed on the Tcl Module path (e.g.
# alongside Tk's own library) so "package require console" resolves.
if {[llength [info commands console]] == 0} {
    proc console {sub args} {
        rename console {}
        package require console
        tailcall console $sub {*}$args
    }
}

