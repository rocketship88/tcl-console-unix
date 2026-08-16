proc cputs {dest {string ""}} { ;# output colorized text and/or font changes to the console
    if { ! [info exist ::tk::my_color_set] } { ;# a default set of colorful output texts
        set ::tk::my_color_set 1
        console eval {
            .console tag configure green            -foreground \#00ff00 -background black -selectbackground grey50
            .console tag configure yellowonblack    -foreground yellow -background black -font {ariel 14 bold}
            .console tag configure yellow           -foreground yellow
            .console tag configure whiteonred       -foreground white -background red
            .console tag configure red              -foreground red
        }
    }
    if { [string index $dest 0] eq "=" } { ;# dynamically add or change a tag, use with dest: {= tagname {attributes...}}
    	lassign $dest eq name value
    	console eval ".console tag configure $name $value" ;# add or modify the tag attributes
        set dest $name	
    }
    # to just change the attributes, the string can be a "" which will not output anything, since we don't add \n like puts does
    console eval [list ::tk::ConsoleOutput $dest $string]
}
proc box {title args} {
	cputs green "                                $title\n"
	cputs green "  "
	cputs stdout "\n"
	foreach item $args {
		cputs green "  "
		if { [string index $item 0] eq "!" } {
			cputs stderr " [string range $item 1 end]\n"	
		} else {
			cputs stdout " $item\n"		
		}
	}
	cputs green "  "
	cputs stdout "\n"
	cputs green "\n"
}

if { 00 } { #example use of box
box  "some tests"  "double-click test" \
                    "!stderr test" \
                    "isatty stdout: [fconfigure stdout -blocking]" \
                    "info nameofexecutable: [info nameofexecutable]"
}

# These 2 unpack/repack can be used instead of console hide/show resp.
# They amount to the same thing except the channel transforms are not
# popped and so the console continues to receive and store puts output
# In addition to these 2 proc's one should also change the meaning of
# the window close box X which otherwise would do a console hide
# these should not be intermixed with console show/hide or things can
# get out of sync. You must do a console show to create the console
# but you can immediately do an unpack
#
# todo: hide the globals geom and packorder in a namespace


proc unpack {} {
    if { [info exist ::packorder] } {
    	return ;# already unpacked
    }
    if { [info commands console] eq "" } {
        return ;# console command not available, nothing to unpack
    }
    
    if {[catch {
        set ::packorder [console eval {pack slaves .}]
        foreach item $::packorder {
            set ::packinfo($item) [console eval "pack info $item"]
        }
        console eval "
            pack forget  $::packorder
            wm withdraw .
        "
    } err_code]} {
        puts $err_code
    }
    set ::geom [console eval {wm geom .}]
}

proc repack {} {
    if {! [info exist ::packorder] } {
    	return ;# can't repack, haven't done an unpack
    } 
    if {[catch {
        foreach item $::packorder {
            console eval "pack $item $::packinfo($item)"
        }
        console eval {wm deiconify .}
    } err_code]} {
        puts $err_code
    }
    catch {console eval "wm geom . $::geom"}
    unset -nocomplain ::packorder ;# ready to be unpacked again
}


console show
console eval {
    # Use WM_DELETE_WINDOW protocol to catch console close and replace the hide with our unpack
    wm protocol . WM_DELETE_WINDOW {
       consoleinterp eval unpack
    }
}
unpack ;# begin unpacked but will still capture data
