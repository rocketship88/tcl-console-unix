# FILE: console.tcl
#
#       Provides a console window.
#
# Last modified on: $Date: 2005-10-15 06:00:15 $
# Last modified by: $Author: jcw $
#
# This file is evaluated to provide a console window interface to the
# root Tcl interpreter of an OOMMF application.  It calls on a script
# included with the Tk script library to do most of the work, making use
# of Tk interface details which are only semi-public.  For this reason,
# there is some risk that future versions of Tk will no longer support
# this script.  That is why this script has been isolated in a file of
# its own.
 
########################################################################
# If the Tcl command 'console' is already in the interpreter, our work
# is done.
########################################################################
if {![catch {console show}]} {
    return
}
 
########################################################################
# Check Tcl/Tk support
########################################################################
if {[catch {package require Tcl 8-}]} {
    package require Tcl 7.5
}

if {[catch {package require Tk 8-}]} {
    if {[catch {package require Tk 4.1}]} {
        return -code error "Tk required but not loaded."
    }
}

set _ [file join $tk_library console.tcl]
if {![file readable $_]} {
    return -code error "File not readable: $_"
}

########################################################################
# Provide the support which the Tk library script console.tcl assumes
########################################################################
# 1. Create an interpreter for the console window widget and load Tk
set consoleInterp [interp create]
$consoleInterp eval [list set tk_library $tk_library]
$consoleInterp alias exit exit
load "" Tk $consoleInterp
 
# 2. A command 'console' in the application interpreter
;proc console {sub {optarg {}}} [subst -nocommands {
    switch -exact -- \$sub {
        title {
            $consoleInterp eval wm title . [list \$optarg]
        }
        hide {
            $consoleInterp eval wm withdraw .
        }
        show {
            $consoleInterp eval wm deiconify .
        }
        eval {
            $consoleInterp eval \$optarg
        }
        default {
            error "bad option \\\"\$sub\\\": should be hide, show, or title"
        }
    }
}]

# 3. Alias a command 'consoleinterp' in the console window interpreter
#       to cause evaluation of the command 'consoleinterp' in the
#       application interpreter.
;proc consoleinterp {sub cmd} {
    switch -exact -- $sub {
        eval {
            uplevel #0 $cmd
        }
        record {
            history add $cmd
            catch {uplevel #0 $cmd} retval
            return $retval
        }
        default {
            error "bad option \"$sub\": should be eval or record"
        }
    }
}
if {[package vsatisfies [package provide Tk] 4]} {
    $consoleInterp alias interp consoleinterp
} else {
    $consoleInterp alias consoleinterp consoleinterp
}

# 4. Bind the <Destroy> event of the application interpreter's main
#    window to kill the console (via tkConsoleExit)
bind . <Destroy> [list +if {[string match . %W]} [list catch \
        [list $consoleInterp eval tkConsoleExit]]]

# 5. Redirect stdout/stderr messages to the console
if {[package vcompare [package present Tcl] 8.6] >= 0} {
    # 5a. we can use TIP#230 channel transforms to achieve this simply:
    namespace eval tkConsoleOut {
        variable consoleInterp $::consoleInterp
        proc initialize {what x mode}    {
            fconfigure $what -buffering none
            return {initialize finalize write flush}
        }
        proc finalize {what x}          { }
proc write {what x data}         { 
    variable consoleInterp
    # Check if interpreter still exists
    if {[interp exists $consoleInterp]} {
        set data [encoding convertfrom utf-8 $data]
        set data [string map {\r ""} $data]
        $consoleInterp eval [list ::tk::ConsoleOutput $what $data]
    } else {
        # Interpreter gone - pass data through to terminal
        return -code error "console closed"
    }
    return ""
}
        proc flush {what x}              { }
        namespace export {[a-z]*}
        namespace ensemble create -parameters what
    }
    
    # Leave encoding as default (utf-8)
    chan push stdout {::tkConsoleOut stdout}
    chan push stderr {::tkConsoleOut stderr}
    
    # Restore normal output if console widget goes away...
# Restore normal output if console widget goes away...
proc Oc_RestorePuts {slave} {
    # Pop the transforms to restore normal output
    catch {chan pop stdout}
    catch {chan pop stderr}
    
    # Restore UTF-8 encoding for the terminal
    catch {fconfigure stdout -encoding utf-8}
    catch {fconfigure stderr -encoding utf-8}
    
    # Test that output is working - this should appear in terminal
    catch {puts stderr "Console closed: output restored to terminal"}
    
    # Delete the console interpreter
    catch {interp delete $slave}
}
} else {    # 5b. Pre-8.6 needs to redefine 'puts' in order to redirect stdout
    #     and stderr messages to the console
    rename puts tcl_puts
    ;proc puts {args} [subst -nocommands {
        switch -exact -- [llength \$args] {
            1 {
                if {[string match -nonewline \$args]} {
                    if {[catch {uplevel 1 [linsert \$args 0 tcl_puts]} msg]} {
                        regsub -all tcl_puts \$msg puts msg
                        return -code error \$msg
                    }
                } else {
                    $consoleInterp eval [list ::tk::ConsoleOutput stdout \
                            "[lindex \$args 0]\n"]
                }
            }
            2 {
                if {[string match -nonewline [lindex \$args 0]]} {
                    $consoleInterp eval [list ::tk::ConsoleOutput stdout \
                            [lindex \$args 1]]
                } elseif {[string match stdout [lindex \$args 0]]} {
                    $consoleInterp eval [list ::tk::ConsoleOutput stdout \
                            "[lindex \$args 1]\n"]
                } elseif {[string match stderr [lindex \$args 0]]} {
                    $consoleInterp eval [list ::tk::ConsoleOutput stderr \
                            "[lindex \$args 1]\n"]
                } else {
                    if {[catch {uplevel 1 [linsert \$args 0 tcl_puts]} msg]} {
                        regsub -all tcl_puts \$msg puts msg
                        return -code error \$msg
                    }
                }
            }
            3 {
                if {![string match -nonewline [lindex \$args 0]]} {
                    if {[catch {uplevel 1 [linsert \$args 0 tcl_puts]} msg]} {
                        regsub -all tcl_puts \$msg puts msg
                        return -code error \$msg
                    }
                } elseif {[string match stdout [lindex \$args 1]]} {
                    $consoleInterp eval [list ::tk::ConsoleOutput stdout \
                            [lindex \$args 2]]
                } elseif {[string match stderr [lindex \$args 1]]} {
                    $consoleInterp eval [list ::tk::ConsoleOutput stderr \
                            [lindex \$args 2]]
                } else {
                    if {[catch {uplevel 1 [linsert \$args 0 tcl_puts]} msg]} {
                        regsub -all tcl_puts \$msg puts msg
                        return -code error \$msg
                    }
                }
            }
            default {
                if {[catch {uplevel 1 [linsert \$args 0 tcl_puts]} msg]} {
                    regsub -all tcl_puts \$msg puts msg
                    return -code error \$msg
                }
            }
        }
    }]
    $consoleInterp alias puts puts
    # Restore normal [puts] if console widget goes away...
proc Oc_RestorePuts {slave} {
    # Pop the transforms first
    catch {chan pop stdout}
    catch {chan pop stderr}
    
    # Reconfigure for terminal
    catch {fconfigure stdout -encoding utf-8 -buffering line}
    catch {fconfigure stderr -encoding utf-8 -buffering none}
    
    # Flush any buffered data
    catch {flush stdout}
    catch {flush stderr}
    
    # Try writing WITHOUT catch to see any errors
    puts stderr "\n=== Console closed: output restored ==="
    flush stderr
    
    # Delete interpreter last
    interp delete $slave
}
}

# 6. No matter what Tk_Main says, insist that this is an interactive  shell
set tcl_interactive 1

########################################################################
# Evaluate the Tk library script console.tcl in the console interpreter
########################################################################
$consoleInterp eval source [list [file join $tk_library console.tcl]]
#$consoleInterp eval {
#    if {![llength [info commands tkConsoleExit]]} {
#        tk::unsupported::ExposePrivateCommand tkConsoleExit
#    }
#}
#$consoleInterp eval {
#    if {![llength [info commands tkConsoleOutput]]} {
#        tk::unsupported::ExposePrivateCommand tkConsoleOutput
#    }
#}
if {[string match 8.3.4 $tk_patchLevel]} {
    # Workaround bug in first draft of the tkcon enhancments
    $consoleInterp eval {
        bind Console <Control-Key-v> {}
    }
}

$consoleInterp alias Oc_RestorePuts Oc_RestorePuts $consoleInterp
$consoleInterp eval {
    # Use WM_DELETE_WINDOW protocol to catch console close before destruction
    wm protocol . WM_DELETE_WINDOW {
        Oc_RestorePuts
        destroy .
    }
}

# addition by Schelte Bron ([sbron]):
# Allow functional pasting with the middle mouse button
catch {
    # on particularly old Tk versions, virtual events might not be present?
    # FIXME: this should be guarded with an appropriate version test
    $consoleInterp eval {
        bind Console <<PasteSelection>> {
            if {$tk_strictMotif || ![info exists tk::Priv(mouseMoved)] \
            || !$tk::Priv(mouseMoved)} {
                catch {
                    set clip [::tk::GetSelection %W PRIMARY]
                    set list [split $clip \n\r]
                    tk::ConsoleInsert %W [lindex $list 0]
                    foreach x [lrange $list 1 end] {
                        %W mark set insert {end - 1c}
                        tk::ConsoleInsert %W "\n"
                        tk::ConsoleInvoke
                        tk::ConsoleInsert %W $x
                    }
                }
            }
        }
    }
}
$consoleInterp eval {
    bind Console <Control-equal> {event generate .console <Control-plus>}
    bind Console <Control-KP_Add> {event generate .console <Control-plus>}
    bind Console <Control-KP_Subtract> {event generate .console <Control-minus>}
}

unset consoleInterp

console title "[wm title .] Console"
