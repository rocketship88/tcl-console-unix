# Copyright (c) 2026 Eric Taylor
# Licensed under the MIT License. See LICENSE file in the project root.
# ================================================================================
# wigglyshapestools-N.0.tm  (DEV/DESIGN-TIME TOOLS MODULE)
# ================================================================================

# (no package provide line -- see note in wigglyshapes-1.0.tm)
#
# REQUIRES wigglyshapes to already be loaded first -- this module
# does NOT declare that as a package dependency (deliberately: each
# .tm is meant to be self-contained with no cross-module
# dependencies declared). The caller is responsible for loading
# wigglyshapes before wigglyshapestools, e.g.:
#
#     package require wigglyshapes
#     package require wigglyshapestools
#
# All shared namespace state (including variables only this module
# uses) is declared in wigglyshapes-1.0.tm's namespace eval block,
# not here -- see the note there. If only this module is loaded
# without wigglyshapes first, procs here will fail with undefined
# variable/array errors -- that failure mode is accepted and
# documented rather than guarded against.

# After creating a fresh item (via oval/wigglyBox) meant to replace
# an existing one, rename it back to the ORIGINAL tag and migrate
# its geometry/metadata entries onto that same key -- discarding the
# throwaway auto-generated tag entirely.
#
# This is what makes a shape's tag stable across any number of
# slider tweaks, drags, or zooms: console history (up-arrow)
# referencing a shape's tag, code holding that tag in a variable, and
# the slider panel's b1/b2/c1/c2 globals all keep working without
# ever needing to learn about a new tag.
#
#   canvas  - the canvas both items live on
#   oldtag  - the tag to preserve (the one callers already know about)
#   newtag  - the just-created item's own fresh auto-generated tag
#   kind    - "oval" or "box", so we migrate the right metadata arrays
proc ::wiggly::retagAndMigrate {canvas oldtag newtag kind} {
    $canvas itemconfigure $newtag -tags [list $oldtag wiggly]
    if {$kind eq "oval"} {
        set ::wiggly::geom($oldtag)     $::wiggly::geom($newtag)
        set ::wiggly::ovalMeta($oldtag) $::wiggly::ovalMeta($newtag)
        unset -nocomplain ::wiggly::geom($newtag) ::wiggly::ovalMeta($newtag)
    } else {
        set ::wiggly::boxGeom($oldtag) $::wiggly::boxGeom($newtag)
        set ::wiggly::boxMeta($oldtag) $::wiggly::boxMeta($newtag)
        unset -nocomplain ::wiggly::boxGeom($newtag) ::wiggly::boxMeta($newtag)
    }
}

# ============================================================
# CONTROL PANEL
# ============================================================

# Store each layer as a FRACTION of segment-count (not an absolute
# frequency), so it can be recomputed near Nyquist (segments/2) for
# a jagged rather than lobed look, and stays fixed per oval so
# sliders scale one wobble instead of re-randomizing it each time.
proc ::wiggly::initBaseWaves {slot maxHarmonics} {
    set waves {}
    for {set i 0} {$i < $maxHarmonics} {incr i} {
        set frac  [expr {0.15 + (0.35 * $i) / double($maxHarmonics)}]
        set phase [expr {rand() * 2 * acos(-1)}]
        lappend waves [list $frac $phase]
    }
    set ::wiggly::baseWaves($slot) $waves
}

# Redraw oval $slot (1 or 2) on $canvas using:
#  - geometry introspected from ::wiggly::geom(current tag)
#  - style introspected from the canvas item itself (itemcget),
#    including any non-default extras like -dash via
#    extraOptionsFromItem
#  - amplitude/segments/harmonics/smooth read live from the slider vars
#  - frequencies derived from the cached base waves, scaled near
#    Nyquist relative to current -segments, for a jagged look
#
# The oval's tag stays stable across the redraw -- the freshly
# created replacement is renamed back onto it via retagAndMigrate,
# so c1/c2 (and anything referencing this tag elsewhere, like console
# history) never has to learn about a new tag.
proc ::wiggly::redrawOvalSlot {canvas slot {value {}}} {
    upvar #0 c$slot tag

    set outline [$canvas itemcget $tag -outline]
    set fill    [$canvas itemcget $tag -fill]
    set lw      [$canvas itemcget $tag -width]
    set extra   [::wiggly::extraOptionsFromItem $canvas $tag]
    lassign $::wiggly::geom($tag) cx cy rx ry

    set n       $::wiggly::harm($slot)
    set amp     $::wiggly::amp($slot)
    set segs    $::wiggly::seg($slot)
    set nyquist [expr {max(2, int($segs / 2))}]

    set active [lrange $::wiggly::baseWaves($slot) 0 [expr {$n - 1}]]
    set waves {}
    foreach w $active {
        lassign $w frac phase
        set freq [expr {max(2, min($nyquist, round($frac * $segs)))}]
        lappend waves [list $freq [expr {$amp / double($n)}] $phase]
    }

    set newtag [::wiggly::oval $canvas $cx $cy $rx $ry \
        -waves $waves -segments $segs \
        -smooth $::wiggly::smooth($slot) \
        -outline $outline -fill $fill -width $lw \
        {*}$extra]
    set ::wiggly::ovalMeta($newtag) [list $amp $segs $n]

    $canvas delete $tag
    unset -nocomplain ::wiggly::geom($tag) ::wiggly::ovalMeta($tag)

    ::wiggly::retagAndMigrate $canvas $tag $newtag oval
    # NOTE: tag (the c1/c2 global) itself never changes -- no
    # "set ctag $newtag" needed anymore.
}

# Redraw box $slot (1 or 2) on $canvas -- same tag-preserving
# approach as redrawOvalSlot above.
proc ::wiggly::redrawBoxSlot {canvas slot {value {}}} {
    upvar #0 b$slot tag

    set outline [$canvas itemcget $tag -outline]
    set fill    [$canvas itemcget $tag -fill]
    set lw      [$canvas itemcget $tag -width]
    set sm      [$canvas itemcget $tag -smooth]
    set extra   [::wiggly::extraOptionsFromItem $canvas $tag]
    lassign $::wiggly::boxGeom($tag) x y dx dy

    set newtag [::wiggly::wigglyBox $canvas $x $y $dx $dy \
        -amplitude $::wiggly::boxAmp($slot) \
        -segments  $::wiggly::boxSeg($slot) \
        -smooth $sm \
        -outline $outline -fill $fill -width $lw \
        {*}$extra]

    $canvas delete $tag
    unset -nocomplain ::wiggly::boxGeom($tag) ::wiggly::boxMeta($tag)

    ::wiggly::retagAndMigrate $canvas $tag $newtag box
}

# Bind mousewheel-over-widget to nudge a scale by one resolution step.
# Windows only needs the sign of %D.
proc ::wiggly::bindMousewheel {scaleWidget} {
    bind $scaleWidget <MouseWheel> {
        %W set [expr {[%W get] + (%D > 0 ? 1 : -1) * [%W cget -resolution]}]
    }
    bind $scaleWidget <Button-4> {
        %W set [expr {[%W get] + [%W cget -resolution]}]
    }
    bind $scaleWidget <Button-5> {
        %W set [expr {[%W get] - [%W cget -resolution]}]
    }
}

# One labelframe containing however many sliders are listed in $entries.
# Each entry is: {label varArrayName slot canvas redrawProc from to res}
proc ::wiggly::makeSliderRow {parent name entries} {
    set lf [labelframe $parent.$name -text [string totitle $name]]
    pack $lf -fill x -padx 8 -pady 4

    foreach e $entries {
        lassign $e label varArray slot canvas redrawProc from to res
        set widget "$lf.s_${varArray}${slot}"

        set ::wiggly::${varArray}($slot) [expr {$from + ($to - $from) / 3}]
        scale $widget -orient horizontal -from $from -to $to \
            -resolution $res -length 160 -label $label \
            -variable ::wiggly::${varArray}($slot) \
            -command [list $redrawProc $canvas $slot]
        pack $widget -side left -expand 1 -fill x -padx 6
        ::wiggly::bindMousewheel $widget
    }
}

# Creates b1, b2, c1, c2 as GLOBAL variables (2 boxes + 2 ovals to
# drive from the sliders), then builds the slider/checkbox panel.
# This is dev/design-time convenience: a package consumer that
# already has its own shapes on the canvas can skip calling this
# and use ::wiggly::wigglyBox / ::wiggly::oval / the inspector
# directly instead.
proc ::wiggly::buildControls {canvas} {
    global b1 b2 c1 c2

    set b1 [::wiggly::wigglyBox $canvas 20 20 150 80 -amplitude 5 -fill lightyellow -outline black]
    set b2 [::wiggly::wigglyBox $canvas 200 60 120 100 -amplitude 8 -segments 10 -outline darkred -width 3]
    set c1 [::wiggly::oval $canvas 150 130 80 80 -fill lightblue -outline navy]
    set c2 [::wiggly::oval $canvas 350 130 90 40 -outline darkred]

    ::wiggly::initBaseWaves 1 30
    ::wiggly::initBaseWaves 2 30

    set top [toplevel .ovalControls]
    wm title $top "Oval & Box Controls"

    makeSliderRow $top amplitude [list \
        [list "Oval 1" amp    1 $canvas ::wiggly::redrawOvalSlot 0 50 1] \
        [list "Oval 2" amp    2 $canvas ::wiggly::redrawOvalSlot 0 50 1] \
        [list "Box 1"  boxAmp 1 $canvas ::wiggly::redrawBoxSlot  0 50 1] \
        [list "Box 2"  boxAmp 2 $canvas ::wiggly::redrawBoxSlot  0 50 1] \
    ]

    makeSliderRow $top segments [list \
        [list "Oval 1" seg    1 $canvas ::wiggly::redrawOvalSlot 8 150 1] \
        [list "Oval 2" seg    2 $canvas ::wiggly::redrawOvalSlot 8 150 1] \
        [list "Box 1"  boxSeg 1 $canvas ::wiggly::redrawBoxSlot  2 40  1] \
        [list "Box 2"  boxSeg 2 $canvas ::wiggly::redrawBoxSlot  2 40  1] \
    ]

    makeSliderRow $top harmonics [list \
        [list "Oval 1" harm 1 $canvas ::wiggly::redrawOvalSlot 1 30 1] \
        [list "Oval 2" harm 2 $canvas ::wiggly::redrawOvalSlot 1 30 1] \
    ]

    set lf [labelframe $top.smooth -text "Smooth (ovals only)"]
    pack $lf -fill x -padx 8 -pady 4
    foreach slot {1 2} {
        set ::wiggly::smooth($slot) 0
        checkbutton $lf.c$slot -text "Oval $slot" \
            -variable ::wiggly::smooth($slot) -onvalue 1 -offvalue 0 \
            -command [list ::wiggly::redrawOvalSlot $canvas $slot]
        pack $lf.c$slot -side left -expand 1 -padx 30
    }

    # Sync the on-screen shapes to the sliders' starting values right
    # away, rather than waiting for the first drag to force a redraw.
    foreach slot {1 2} {
        ::wiggly::redrawOvalSlot $canvas $slot
        ::wiggly::redrawBoxSlot  $canvas $slot
    }
}

# ============================================================
# INSPECTOR (right-click to print reproduction code)
# ============================================================

# Right-click any wiggly shape on $canvas to print the reproduction
# command, an itemconfigure introspection line, and its result.
# Left click is used by enableInteraction; right click stays free
# here.
#
# Uses ::wiggly::_clickedTag / ::wiggly::_call / ::wiggly::_tag as
# scratch variables rather than locals, since bind scripts execute
# at global scope -- an unqualified `lassign ... call tag` here
# would otherwise silently create real globals ::call/::tag rather
# than anything namespace-scoped.
proc ::wiggly::enableInspector {canvas} {
    $canvas bind wiggly <Button-3> {
        set ::wiggly::_clickedTag [::wiggly::uniqueTagOf %W current]
        if {$::wiggly::_clickedTag ne ""} {
            lassign [::wiggly::wigglyInfo %W $::wiggly::_clickedTag] ::wiggly::_call ::wiggly::_tag
            puts " $::wiggly::_call\n\n %W itemconfigure $::wiggly::_tag \n\n [%W itemconfigure $::wiggly::_tag]"
        }
    }
}

# ============================================================
# DRAG-TO-MOVE (cheap: delete + recreate on release)
# ============================================================

proc ::wiggly::dragStart {canvas x y} {
    set item [$canvas find withtag current]
    if {$item eq ""} { return }
    set tag [::wiggly::uniqueTagOf $canvas $item]
    if {$tag eq ""} { return }

    set ::wiggly::_dragTag    $tag
    set ::wiggly::_dragStartX [$canvas canvasx $x]
    set ::wiggly::_dragStartY [$canvas canvasy $y]

    # rubber-band preview line, start collapsed to a single point
    set ::wiggly::_dragLineTag [$canvas create line \
        $::wiggly::_dragStartX $::wiggly::_dragStartY \
        $::wiggly::_dragStartX $::wiggly::_dragStartY \
        -fill gray50 -dash {4 2} -width 1 -tags dragpreview]
}

proc ::wiggly::dragMove {canvas x y} {
    if {$::wiggly::_dragTag eq ""} { return }
    set cx [$canvas canvasx $x]
    set cy [$canvas canvasy $y]

    # cheap redraw of the preview line: delete + recreate, same
    # spirit as the object move itself, rather than a persistent
    # item we reconfigure -- either works, this just matches style
    $canvas delete $::wiggly::_dragLineTag
    set ::wiggly::_dragLineTag [$canvas create line \
        $::wiggly::_dragStartX $::wiggly::_dragStartY $cx $cy \
        -fill gray50 -dash {4 2} -width 1 -tags dragpreview]
}

# On release: compute net displacement, delete the old item, and
# recreate it at the shifted location using wigglyInfo's reproduction
# command (which also carries forward any non-default extras like
# -dash). Cheap -- one delete + one create, not a redraw per pixel of
# motion. The wobble's random phase re-rolls on every drag since
# recreation goes through oval/wigglyBox again rather than literally
# translating existing coordinates. The tag itself is preserved via
# retagAndMigrate -- see its docstring.
proc ::wiggly::dragEnd {canvas x y} {
    if {$::wiggly::_dragTag eq ""} { return }
    set tag $::wiggly::_dragTag
    set ::wiggly::_dragTag ""

    $canvas delete $::wiggly::_dragLineTag
    set ::wiggly::_dragLineTag ""

    set dx [expr {[$canvas canvasx $x] - $::wiggly::_dragStartX}]
    set dy [expr {[$canvas canvasy $y] - $::wiggly::_dragStartY}]

    lassign [::wiggly::wigglyInfo $canvas $tag] cmd _
    set kind [::wiggly::kindOf $tag]

    # cmd is: ::wiggly::oval canvas cx cy rx ry -opt val ...
    #     or: ::wiggly::wigglyBox canvas x y dx dy -opt val ...
    # position args are always at index 2 and 3 -- shift them.
    set cmd [lreplace $cmd 2 2 [expr {[lindex $cmd 2] + $dx}]]
    set cmd [lreplace $cmd 3 3 [expr {[lindex $cmd 3] + $dy}]]

    $canvas delete $tag
    if {$kind eq "oval"} {
        unset -nocomplain ::wiggly::geom($tag) ::wiggly::ovalMeta($tag)
    } else {
        unset -nocomplain ::wiggly::boxGeom($tag) ::wiggly::boxMeta($tag)
    }

    set newtag [eval $cmd]
    ::wiggly::retagAndMigrate $canvas $tag $newtag $kind
}

# Left-click-drag any wiggly shape on $canvas: shows a dashed
# rubber-band line from mousedown to the current mouse position
# while dragging, then on release deletes the old shape and
# recreates it shifted by the net displacement, keeping the same
# tag throughout.
proc ::wiggly::enableDragBindings {canvas} {
    $canvas bind wiggly <ButtonPress-1>   [list ::wiggly::dragStart $canvas %x %y]
    $canvas bind wiggly <B1-Motion>       [list ::wiggly::dragMove  $canvas %x %y]
    $canvas bind wiggly <ButtonRelease-1> [list ::wiggly::dragEnd   $canvas %x %y]
}

# ============================================================
# ZOOM (Control-MouseWheel: shape zoom or canvas resize)
# ============================================================

# Scale one shape's geometry by `factor` (>1 grows, <1 shrinks),
# keeping it centered on its own current center point. Recreates the
# item via the same delete+recreate+retag pattern as dragEnd, so
# style/extras (-dash, etc) and the shape's tag are preserved.
proc ::wiggly::zoomTag {canvas tag factor} {
    set kind [::wiggly::kindOf $tag]
    lassign [::wiggly::wigglyInfo $canvas $tag] cmd _

    if {$kind eq "oval"} {
        # cmd: ::wiggly::oval canvas cx cy rx ry ...
        # cx/cy untouched -- scaling rx/ry alone keeps it centered
        set rx [expr {[lindex $cmd 4] * $factor}]
        set ry [expr {[lindex $cmd 5] * $factor}]
        set cmd [lreplace $cmd 4 4 $rx]
        set cmd [lreplace $cmd 5 5 $ry]
    } else {
        # cmd: ::wiggly::wigglyBox canvas x y dx dy ...
        # x/y is the upper-left corner, so we recompute it from the
        # box's center to keep the resize symmetric rather than
        # growing only toward the bottom-right
        set x  [lindex $cmd 2]
        set y  [lindex $cmd 3]
        set dx [lindex $cmd 4]
        set dy [lindex $cmd 5]
        set cx [expr {$x + $dx / 2.0}]
        set cy [expr {$y + $dy / 2.0}]
        set ndx [expr {$dx * $factor}]
        set ndy [expr {$dy * $factor}]
        set cmd [lreplace $cmd 2 2 [expr {$cx - $ndx / 2.0}]]
        set cmd [lreplace $cmd 3 3 [expr {$cy - $ndy / 2.0}]]
        set cmd [lreplace $cmd 4 4 $ndx]
        set cmd [lreplace $cmd 5 5 $ndy]
    }

    $canvas delete $tag
    if {$kind eq "oval"} {
        unset -nocomplain ::wiggly::geom($tag) ::wiggly::ovalMeta($tag)
    } else {
        unset -nocomplain ::wiggly::boxGeom($tag) ::wiggly::boxMeta($tag)
    }

    set newtag [eval $cmd]
    ::wiggly::retagAndMigrate $canvas $tag $newtag $kind
}

# Resize the canvas WIDGET itself (more/less visible area) -- does
# NOT rescale existing shapes to fit, so shrinking can clip content.
proc ::wiggly::zoomCanvas {canvas factor} {
    set neww [expr {round([$canvas cget -width]  * $factor)}]
    set newh [expr {round([$canvas cget -height] * $factor)}]
    $canvas configure -width $neww -height $newh

    # force the toplevel back into automatic-geometry mode, in case
    # a manual window resize (dragging the corner) had switched it
    # into user-override mode, where it stops auto-fitting to its
    # children's requested size
    wm geometry [winfo toplevel $canvas] {}
}

# Single Control-MouseWheel handler for the whole canvas: if the
# pointer is currently over a wiggly shape, zoom that shape; if it's
# over empty canvas, resize the canvas instead. No separate item-tag
# binding needed -- "current" is already tracked continuously by the
# canvas as the mouse moves, so one widget-level binding covers both.
proc ::wiggly::zoomAt {canvas delta} {
    set factor [expr {$delta > 0 ? 1.1 : (1.0 / 1.1)}]
    set item [$canvas find withtag current]
    if {$item ne ""} {
        set tag [::wiggly::uniqueTagOf $canvas $item]
        if {$tag ne ""} {
            ::wiggly::zoomTag $canvas $tag $factor
            return
        }
    }
    ::wiggly::zoomCanvas $canvas $factor
}

# Sets up BOTH left-click-drag-to-move AND Control-mousewheel zoom
# (shape zoom when hovering a shape, canvas resize when hovering
# empty space) on $canvas in one call.
proc ::wiggly::enableInteraction {canvas} {
    ::wiggly::enableDragBindings $canvas
    bind $canvas <Control-MouseWheel> [list ::wiggly::zoomAt $canvas %D]
    bind $canvas <Control-Button-4> [list ::wiggly::zoomAt $canvas 1]
    bind $canvas <Control-Button-5> [list ::wiggly::zoomAt $canvas -1]
}

