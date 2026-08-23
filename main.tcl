# main.tcl
#
# This file can be sourced to enable some debugging commands
# l* where we have la lh lf lg lw lp lpm ls and ltree
# for list array, history, file, globals, widget, proc, method, folder, and widget tree
#
# also enables some extra console buttons and an extra menu
# the gui widget tree tool needs BWidgets, it will also add
# [pwd] to auto_path
#
# can also be run as
#
# wish main.tcl myprogram.tcl arg1 arg2 ...
#
# main.tcl will be sourced first, then it will shift the args
# and source myprogram.tcl which will think it was the only
# file called as argv0 and argv will be arg1 arg2 ... and argc set correctly
#
#



# my startup module, simply source it
catch {source colon-1.0.tm}
interp alias {} lds {} tcl::unsupported::disassemble ;# shorthands 
history keep 1000 ;# enlarge history in console
catch {wm iconbitmap . -default //zipfs:/app/APP.ico}

console eval {
#    catch {wm iconbitmap . //zipfs:/app/APP.ico}
    bind . <Control-MouseWheel> {
        if {%D > 0} {
#            .menubar.edit invoke 6
            event generate .console <<Console_FontSizeIncr>>
        } else {
#            .menubar.edit invoke 7
            event generate .console <<Console_FontSizeDecr>>
        }
    }
    .console configure -inactiveselectbackground grey50
    
    set ::tk::console::maxLines 100000
    set ::tk::console::toggle   0
	set ::tk::do_scroll 1
    proc ::tk::ConsoleSeeOutput {} {
        if {$::tk::do_scroll} {.console see insert}
        set ::tk::console::seecount 0
    }
    proc ::tk::ConsoleOutput {dest string} { ;# adds throttle to improve console performance
        set count 25
        set w .console
        $w insert output $string $dest
        ::tk::console::ConstrainBuffer $w $::tk::console::maxLines
         if { $::tk::console::toggle } { ;# check button toggle for testing speed up
            if {$::tk::do_scroll} {$w see insert}  ;# this is standard console
            return
        }
        incr ::tk::console::seecount
        if { $::tk::console::seecount < $count} {
            if {$::tk::do_scroll} {$w see insert}
        } elseif { $::tk::console::seecount == $count } {
            after 100 ::tk::ConsoleSeeOutput
        }
    }

    
}
proc ltree {{root .} {level 0}} {					# list widget tree
	set children [winfo children $root]
	set class [winfo class $root]
	set info ""
	if       { $class == "Button" } {
		set info [split [$root cget -text] \n]
	
	} elseif { $class == "TLabelframe" } {
		set info [split [$root cget -text] \n]
	
	} elseif { $class == "TButton" } {
		set info [split [$root cget -text] \n]
	
	} elseif { $class == "TEntry" } {
		set info "var: [$root cget -textvariable]"
	} elseif { $class == "TCheckbutton" } {
		set info [split [$root cget -text] \n]
	} elseif { $class == "TButton2" } {
		set info [split [$root cget -text] \n]
	} else {
	
	}

	# Determine actual pack containment, which can differ from the
	# Tk widget-hierarchy parent when a widget is packed via -in
	# into a container that isn't its real winfo parent.
	set packnote ""
	if {[winfo manager $root] eq "pack"} {
		set pinfo [pack info $root]
		set idx [lsearch $pinfo "-in"]
		if {$idx >= 0} {
			set packparent [lindex $pinfo [expr {$idx + 1}]]
			set realparent [winfo parent $root]
			if {$packparent ne $realparent} {
				set packnote "  (packed -in $packparent)"
			}
		}
	}

	puts -nonewline "[string repeat " |  " $level]"
	puts -nonewline "$root"
	puts -nonewline " - $class  $info$packnote\n"
	if { $children == "" } {
		return $root
	} else {
		foreach child $children {
			set tout [ltree $child [expr ( $level + 1 )]]
		}
		
	}	
}

proc lh {{range {}}} {
    set last [expr {[history nextid] - 1}]
    if {$range eq ""} {
        set lo 1; set hi $last
    } elseif {$range eq "-"} {
        puts [history]
        return
    } elseif {[regexp {^(\d+)-(\d+)$} $range -> lo hi]} {
        # lo/hi set by regexp
    } else {
        set lo $range; set hi $range
    }
    for {set i $lo} {$i <= $hi} {incr i} {
        if {![catch {history event $i} cmd]} {
            puts $cmd
        }
    }
}
proc lf {filename} {
    set f [open $filename]
    puts [read $f]
    close $f
}
proc ls {{pat *} {dir .}} {
    set dirs {}
    set files {}

    foreach f [glob -nocomplain -directory $dir $pat] {
        if {[file isdirectory $f]} {
            lappend dirs $f
        } else {
            lappend files $f
        }
    }

    foreach f [lsort $dirs] {
        set name [file tail $f]
        set mtime [clock format [file mtime $f] -format {%m/%d/%Y %I:%M %p}]
        puts [format "%s %14s  %s  %s" "d" "" $mtime $name]
    }

    foreach f [lsort $files] {
        set name [file tail $f]
        set size [file size $f]
        set mtime [clock format [file mtime $f] -format {%m/%d/%Y %I:%M %p}]
        puts [format "%s %14s  %s  %s" " " [comma $size] $mtime $name]
    }
}
proc la {array_name {pattern *} {rev 0} {xp 0}} { # list an array
upvar 1 $array_name array
    if {![array exists array]} {
		error "\"$array_name\" isn't an array"
    }
	set maxl 0
	foreach name [lsort [array names array $pattern]] {
		if {[string length $name] > $maxl} {
			set maxl [string length $name]
		}
	}
	set maxl [expr {$maxl + [string length $array_name] + 2}]
	if {$rev == 0} {
		foreach name [lsort -dictionary [array names array $pattern]] {
			set nameString [format %s(%s) $array_name $name]
			if {$xp} {
						xputs [format "%-*s = %s" $maxl $nameString $array($name)]
			} else {
						puts stdout [format "%-*s = %s" $maxl $nameString $array($name)]
			}
		}
	} else {
		foreach name [lsort [array names array]] {
			#puts stdout "compare pattern $pattern with $name - $array($name)"
			if {[string match "*$pattern*" $array($name)]} {
				set nameString [format %s(%s) $array_name $name]
				if {$xp} {
					xputs [format "%-*s = %s" $maxl $nameString $array($name)]
				} else {
					puts stdout [format "%-*s = %s" $maxl $nameString $array($name)]
				}
			}
		}

	}
}
proc lw {widget} {	  # list a widget
#puts "widget= |$widget| "
	set w [$widget configure]
	foreach item $w {
		set opt [lindex $item 0]
		set val "---"
		catch {set val [$widget cget $opt]}
		set wid($opt) $val 
    }	
	#la wid
	set names [lsort -dictionary [array names wid]]
	set n [llength $names]
	set n2 [expr ( $n/2 )]
	set odd [expr ( $n % 2 )]
	#puts "odd=$odd n=$n n2=$n2"
	if { $odd } {
		incr n2  ;# so this one is 1 more than half
	}
	#puts "Odd=$odd n=$n n2=$n2"
	if { $odd } {
		for {set m 0;set m2 [expr ( $m+$n2 )]} {$m < $n2} {incr m;incr m2} {
			
			if { $m == $n2-1 } {
#				puts "m = $m"	
				set left [lindex $names $m]
#				puts "l $left      $wid($left)"
				set leftt [format {%-20s %-20s} $left $wid($left)]
				puts "$leftt|"
			
			} else {
#				puts "m = $m,   m2 = $m2"	
				set left [lindex $names $m]
				set right [lindex $names $m2]
				#puts "l $left      $wid($left)"
				#puts "r $right      $wid($right)"
				set leftt [format {%-20s %-20s} $left $wid($left)]
#				cputs green "[string length $leftt] $left $wid($left)\n"
				if { [string length $leftt] > 41 } {
					set leftt [format {%s %s} $left $wid($left)]
					set leftt [string range [format %-41s $leftt] 0 40]
				}
				set rightt [format {%-20s %-20s} $right $wid($right)]
				puts "$leftt|[string trimright $rightt]"
			}
		}

	} else {
		for {set m 0;set m2 [expr ( $m+$n2 )]} {$m < $n2} {incr m;incr m2} {
			#puts "m = $m,   m2 = $m2"	
				set left [lindex $names $m]
				set right [lindex $names $m2]
#				puts "l $left      $wid($left)"
#				puts "r $right      $wid($right)"
				set leftt [format {%-20s %-20s} $left $wid($left)]
#				cputs green "[string length $leftt] $left $wid($left)\n"
				if { [string length $leftt] > 41 } {
					set leftt [format {%s %s} $left $wid($left)]
					set leftt [string range [format %-41s $leftt] 0 40]
				}
				set rightt [format {%-20s %-20s} $right $wid($right)]
				puts "$leftt|[string trimright $rightt]"
		}
		
	}
}

proc lp {{namepat *}} { # list procedure(s)
foreach proc [info procs $namepat] {
		set space ""
		puts -nonewline "#---------------------\nproc $proc {"
		foreach arg [info args $proc] {
			if [info default $proc $arg value] {
				puts -nonewline "$space{$arg $value}"
			} else {
				puts -nonewline $space$arg
			}
			set space " "
		}
		# No newline needed because info body may return a
		# value that starts with a newline
		puts -nonewline "} {"
		puts -nonewline  [info body $proc]
		puts "}"
	}
}
proc lpm {class method} {
    lassign [info class definition $class $method] arglist body
    puts "#---------------------"
    puts "# $class method $method"
    puts "oo::define $class \{"
    puts "    method $method \{$arglist\} \{"
    puts $body
    puts "    \}"
    puts "\}"
}

set ::___lg___ [info global *] ; lappend ___lg___ ___lg___ ;# initial set of globals to not list by default (* = all, **= default)
#console show
proc lg {{pat **} {delimeter |} {max 80}} {          # list globals
    set a [lsort -dictionary [info global ${pat}*]]
    foreach gvar $a {
    	if { $gvar in $::___lg___  && $pat eq "**"} {
    		continue
    	}
        if {[array exists ::$gvar]} { ;# it is an array get some indices
            set val "() [lsort -dictionary [array names ::$gvar]]"
        } elseif { [info exists ::${gvar}] } {
            set val ${delimeter}[set ::${gvar}]$delimeter
            regsub -all {\n} $val [apply {code {eval set str "\\u[string map "U+ {}" $code]"}} 2936] val ;# or 21B2
        } else {
        	continue ;# skip if we cant get the value
        }
        catch {
            puts [format "--- %-20s = %s" $gvar [string range $val 0 $max]]
        }
    }
}


proc comma {num {sep ,}} {
	if { $num < 0 } {
		return "-[comma [expr {(0 - $num )}]]"
	} else {
		while {[regsub {^([-+]?\d+)(\d\d\d)} $num "\\1$sep\\2" num]} {}
	}
	return $num
}


proc wait { ms } {
	set uniq [incr ::__sleep__tmp__counter]
	set ::__sleep__tmp__$uniq 0
	after $ms set ::__sleep__tmp__$uniq 1
	vwait ::__sleep__tmp__$uniq
	unset ::__sleep__tmp__$uniq
}
proc timeus {args} {
    set result [uplevel 1 time $args]
    set number [format %.3f [expr {( [lindex $result 0] / 1. )}]]
    set number [regsub -all {\d(?=(\d{3})+($|\.))} $number {\0,}]
    return "[format %12s $number ] microseconds [lrange $result 2 end]"
}
proc timems {args} {
    set result [uplevel 1 time $args]
    set number [format %.3f [expr {( [lindex $result 0] / 1000. )}]]
    set number [regsub -all {\d(?=(\d{3})+($|\.))} $number {\0,}]
    return "[format %12s $number ] milliseconds [lrange $result 2 end]"
}

proc rangeof {args} { ;# prototype range command (will be called lseq in 8.7 / 9.0 )
    lassign $args a op b by step
    if { $by eq "" } {
        set by by
    }
    if { $step eq "" } {
        set step 1
        set nostep 1
    } else {
        set nostep 0
    }
    set l [llength $args]
    if       { $l < 1 } {
        error "missing args for range"
    } elseif { $l == 1 } { ;#python compatible
        if { $a <= 0 } {
            return {}
        }
        set b [uplevel ": $a"]
        set a 0
        set op ..<
    } elseif { $l == 2 } {;#python compatible just 2 integers, from ..< to
        set a [uplevel ": $a"]
        set b [uplevel ": $op"]
        set op ..<
    } elseif { $l == 3 } {
        if { [string is integer $op] || ($op ne ".." && $op ne "..<" && $op ne "to" && $op ne "..=" && $op ne "-count")} {;#python compatible, all 3 must be integers (or expressions)
            set a [uplevel ": $a"]
            set step [uplevel ": $b"]
            set b $op
            set op ..<
            set by by
        }
    }
    
    set inc 1
    if { $op eq "..<" } {
        set inc 0
        set op ".."
    }
#   puts "a= |$a| b= |$b| step= |$step| nostep= |$nostep| "
    if       { $op eq ".." || $op eq "to" || $op eq "..="} {
    	set a [uplevel ": $a"]
    	set b [uplevel ": $b"]
    	set step [uplevel ": $step"]
        if { $a > $b && $step > 0 && $nostep == 1} {
            set step [expr {   0 - $step   }]
        }
        if { $step == 0 || ($step < 0 && $a <= $b) || ($step > 0 && $b < $a && $nostep)} {
            return {}
        }
        if { $by ne "by" } {
            error "range: unknown term for by : $by"
        }
        set ostep $step
        set step [expr {   abs($step)   }]
        set result {}
        if { $a <=  $b } {
            set nitems [expr {   int( ($b - $a + $step) / $step )   }]
            for {set m 0} {$m < $nitems } {incr m} {
                set e [expr {   $a + $m * $step    }]
                if {!$inc && $e >= $b  } {
                    break
                }
                lappend result $e
            }
        } else {
            set nitems [expr {   int( ($a - $b - $ostep) / (-$ostep) ) }]
            for {set m 0} {$m < $nitems } {incr m} {
                set e [expr {   $a - $m * $step    }]
                if {!$inc && $e <= $b  } {
                    break
                }
                lappend result $e
            }
        }
        return $result
    } elseif { $op eq "-count" } {
    	set a [: a-step]
    	set b [: $b]
#        set a [expr {   $a - $step   }]
        lmap b [lrepeat [expr {   int($b)   }] 0] {set a [expr {   $a + $step   }]}
    } else {
        error "unknown range op $op"
    }
}
proc valueof {args} {
	if {[string first "\[" $args] != -1 || [string first "\$" $args] != -1} {
	 error "Invalid expression $args"
	}
	uplevel 2 = $args
}

if {[package vcompare [info patchlevel] 9.0] >= 0} {
	proc range {a {to to} {b -none-} {by by} {step 1}} {
		if { $b eq "-none-" && ($to eq "to" || $to eq "..") }  {
			set a [uplevel "= $a"]
			return [lseq $a]
		}
		set a [valueof $a]
		set b [valueof $b]
		set step [valueof $step]
#		puts "a4= |$a| to= |$to| b= |$b| by= |$by| step= |$step| "
		return [lseq $a to $b by $step]
	}
} else {
	proc range {a {to to} {b -none-} {by by} {step 1}} {
		if { $b eq "-none-" && ($to eq "to" || $to eq "..") }  {
			set a [uplevel "= $a"]
			return [rangeof $a]
		}
		
		set a [uplevel "= $a"]
		set b [uplevel "= $b"]
		set step [uplevel "= $step"]
		return [rangeof $a to $b by $step]
	}
}
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



proc con+ {args} { ;# add extra buttons to console
	if { $::tcl_platform(platform)    != "windows" && [info commands console] ne "console"} {
		puts "need console for non windows system"
	} else {
###########################################################
## Procedure:  wtree


        proc wtree_:_node_puts {args} {
        	puts ""
        	puts ""
        	cputs green "$args\n"
        	lw $args
#        	catch {cputs green "[pack info $args]\n"}
        	if [catch {
        		set zzz [pack info $args]
        		cputs green "pack: $zzz\n" 
        	} err_code] {
        		if [catch {
        			set zzz [grid info $args]
        			cputs green "grid: $zzz\n" 
        		} err_code] {
        		}
        	}
        	clipboard clear ; clipboard append $args
        }
        proc wtree_:_node_openclose {which} {
        	set nodes [.wtree_top.sw.t nodes root]
        	#puts "which - $which - $nodes"
        	if { $which == "open" } {
        		foreach item $nodes {
        			.wtree_top.sw.t opentree $item
        		}
        	
        	} else {
        		foreach item $nodes {
        			.wtree_top.sw.t closetree $item
        		}
        		
        	}
        }
        
        proc wtree {{root .} {level 0}} {
        	set top .wtree_top
        	if {  $level == 0} {
        		package require BWidget
        		catch {
        			$top.sw.t delete [$top.sw.t nodes root]
        			destroy $top
        		}
        		toplevel $top
        		frame $top.f
        		button $top.f.b1 -text open -command {wtree_:_node_openclose open}
        		button $top.f.b2 -text close -command {wtree_:_node_openclose close}
        		pack $top.f  -side top -fill x
        		pack $top.f.b1 $top.f.b2 -side left -expand yes -fill both
        		ScrolledWindow $top.sw
        		pack $top.sw -fill both -expand 1 -side top
        		Tree $top.sw.t  -deltay 25 -deltax 25 -padx 5 -borderwidth 8 -linesfill orange -padx 5
        		#pack $top.sw.t
        		$top.sw setwidget $top.sw.t   ;# Make ScrolledWindow manage the Tree widget
        		update                ;# Process all UI events before moving on.
        		$top.sw.t bindText <1> +wtree_:_node_puts
        		$top.sw.t bindText <3> "+$top.sw.t opentree "
        		$top.sw.t bindText <Shift-3> "+$top.sw.t closetree " ;# xxxxxxxxx here xxxxxxxxxx
        		set ::wtree_queued_inserts {}
        		wm geom $top 466x326+52+52
        		
        	}
        	set children [winfo children $root]
        	set class [winfo class $root]
        	set info ""
        	if       { $class == "Button" } {
        		set info [split [$root cget -text] \n]
        		
        	} elseif { $class == "TLabelframe" } {
        		set info [split [$root cget -text] \n]
        		
        	} elseif { $class == "TButton" } {
        		set info [split [$root cget -text] \n]
        		
        	} elseif { $class == "TEntry" } {
        		set info "var: [$root cget -textvariable]"
        	} elseif { $class == "TCheckbutton" } {
        		set info [split [$root cget -text] \n]
        	} elseif { $class == "TButton2" } {
        		set info [split [$root cget -text] \n]
        	} else {
        		
        	}
        	
        	#cputs normal "[string repeat " |  " $level]"
        	#cputs green "$root"
        	#cputs red  [split $root .]
        	#cputs normal " - $class  $info\n"
        	set root [regsub -all : $root _]
        	set parts [split [string range $root 1 end] .]
        	#puts "parts = $parts"
        	if { $parts == "" } {
        		set parent root
        	} else {
        		set parent {}
        		foreach item [lrange $parts 0 end-1] {
        			append parent .$item
        		}
        	}
        	#puts "parent = /$parent/"
        	if { $parent == "" } {
        		set parent root
        	}
        	
        	
        	# Determine actual pack containment, which can differ from the
        	# Tk widget-hierarchy parent when a widget is packed via -in
        	# into a container that isn't its real winfo parent.
        	set packnote ""
        	if {[winfo manager $root] eq "pack"} {
        		set pinfo [pack info $root]
        		set idx [lsearch $pinfo "-in"]
        		if {$idx >= 0} {
        			set packparent [lindex $pinfo [expr {$idx + 1}]]
        			set realparent [winfo parent $root]
        			if {$packparent ne $realparent} {
        				set packnote "  (packed -in $packparent)"
        			}
        		}
        	}
        	
        	
        	set cmd "$top.sw.t insert end \{$parent\}   \{$root\}       -font {courier 12} -text  \{$root - $class $info$packnote\}"
        	#puts "cmd = $cmd"
        	lappend ::wtree_queued_inserts $cmd
        	
        	
        	
        	if { $children == "" } {
        		return $root
        	} else {
        		foreach child $children {
        			set tout [wtree $child [expr ( $level + 1 )]]
        		}
        		
        	}
        	if { $level == 0 } {
        		#puts "\n\ndone here\n\n"
        		foreach item $::wtree_queued_inserts {
        			#puts "do - $item"
        			eval $item
        		}
        	}
        	wm geom .wtree_top 998x527+52+52
        }
		if [catch {
			console eval {
				
				if { ![info exist ::tk::conplus] } {
                    if { [string compare [info patch] "8.6"] >= 0 } {
                    	set menuincr 1
                    } else {
                    	set menuincr 0
                    }
					
#					proc console stuff
					set vers [split [info patch] .]
                    if {[catch {
                        .console config -inactiveselectbackground grey50 -tabs {32 left} -tabstyle wordprocessor -width 30
                    } err_code]} {
                    	puts $err_code 
                    }
					wm geom . 110x30+446+9
					bind all <Button-3> {.menubar.edit invoke 2}
					bind all <Control-Button-3> {.menubar.edit invoke 1;.menubar.edit invoke 2}
					pack forget .console .sb .consoleframe
					
					pack [frame  .frame -bg black] -side left -fill y -ipady 10 -pady 10
					#pack [button .frame.eval -text Cev  -command {clipboard clear; clipboard append "console eval \{\}"; .menubar.edit invoke 2}] -side top -fill x
					pack [button .frame.clear -bg white -fg black -text Clear -command {.menubar.file invoke 2}] -side top -fill x
#					pack [button .frame.smaller -bg white -text {font -} -command {.menubar.edit invoke [expr ( $menuincr+6 )];after 100 {.frame.repos invoke}}] -side top -fill x
#					pack [button .frame.bigger  -bg white -text {font +} -command {.menubar.edit invoke [expr ( $menuincr+5 )];after 100 {.frame.repos invoke}}] -side top -fill x
					pack [button .frame.exit     -bg white -text Exit -command {exit}] -side top -fill x
					pack [button .frame.repos -bg white -text BottOM -command {.console see end; .console mark set insert end}] -side top -fill x
					pack [frame  .frame.frame -bg black] -side top -fill x
					pack [button .frame.frame.pm20 -bg gray -text -x -command {wm geom . [expr [lindex [split [wm geom .] x] 0]-10]x[lindex [split [wm geom .] x] 1]}] -side left -fill x -expand 1
					pack [button .frame.frame.pp20 -bg gray -text +x -command {wm geom . [expr [lindex [split [wm geom .] x] 0]+10]x[lindex [split [wm geom .] x] 1]}] -side left -fill x -expand 1
					
#					.frame.bigger invoke;.frame.bigger invoke;.frame.bigger invoke;.frame.bigger invoke
					
					
					pack [checkbutton .frame.scroll -bg white -fg black  -text scroll -variable ::tk::do_scroll] -side top -fill x
					pack .consoleframe -in . -anchor center -expand 1 -fill both -ipadx 0 -ipady 0 -padx 0 -pady 0 -side left
					pack .console -in .consoleframe -anchor center -expand 1 -fill both -ipadx 0 -ipady 0 -padx 1 -pady 1 -side left
					pack .sb -in .consoleframe -anchor center -expand 0 -fill both -ipadx 0 -ipady 0 -padx 1 -pady 1 -side right
					.menubar add casc -label Extra2 -menu [menu .menubar.extra -tearoff 0]
					proc menu+ {head label cmd} {
						set cmd2 [list consoleinterp eval $cmd]
						.menubar.$head add command -label $label -command $cmd2
					}
					menu+ extra {Widget Tree} {wtree}
				}
				set ::tk::conplus yes
                foreach w {.frame.clear .frame.exit .frame.repos .frame.scroll \
                           .frame.frame.pm20 .frame.frame.pp20 \
                           .frame.bigger .frame.smaller} {
                    catch {$w configure -takefocus 0}
                }
                unset w
			}
		} errstr ] {
		    tk_messageBox -message "error = $errstr" -type ok
#			puts stderr "error = $errstr"
		}
	}
	
}
proc tcl::mathfunc::between {a b c} {
	if       { $b < $a } {
		return $a
	} elseif { $b > $c } {
		return $c
	} else {
		return $b
	}
}

#console show
lappend auto_path [pwd]
if { $argv eq "" } {
    console show
    con+
    rename con+ ""
} else {
    con+
    rename con+ ""
    set argv0 [file normalize [lindex $argv 0]]
    set argv [lrange $argv 1 end]
    incr argc -1
    source $argv0
}
