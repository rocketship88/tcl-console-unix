# ::tk::ConsoleOutput --
#
# This routine is called directly by ConsolePutsCmd to cause a string
# to be displayed in the console.
#
# Arguments:
# dest -	The output tag to be used: either "stderr" or "stdout".
# string -	The string to be displayed.

proc ::tk::ConsoleOutput {dest string} {
    set w .console
    $w insert output $string $dest
    ::tk::console::ConstrainBuffer $w $::tk::console::maxLines
    $w see insert
}
