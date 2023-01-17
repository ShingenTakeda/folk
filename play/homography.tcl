package require math::linearalgebra

set points {
    {527 357 1519 1423}
    {560 367 1663 1456}
    {425 289 1103 1151}
    {458 296 1232 1168}
}
for {set i 0} {$i < [llength $points]} {incr i} {
    lassign [lindex $points $i] x$i y$i u$i v$i
}

set A [subst {
    {$x0 $y0 1 0   0   0 [expr -$x0*$u0] [expr -$y0*$u0]}
    {$x1 $y1 1 0   0   0 [expr -$x1*$u1] [expr -$y1*$u1]}
    {$x2 $y2 1 0   0   0 [expr -$x2*$u2] [expr -$y2*$u2]}
    {$x3 $y3 1 0   0   0 [expr -$x3*$u3] [expr -$y3*$u3]}
    {0   0   0 $x0 $y0 1 [expr -$x0*$v0] [expr -$y0*$v0]}
    {0   0   0 $x1 $y1 1 [expr -$x1*$v1] [expr -$y1*$v1]}
    {0   0   0 $x2 $y2 1 [expr -$x2*$v2] [expr -$y2*$v2]}
    {0   0   0 $x3 $y3 1 [expr -$x3*$v3] [expr -$y3*$v3]}
}]

set b [list $u0 $u1 $u2 $u3 $v0 $v1 $v2 $v3]

lassign [math::linearalgebra::solvePGauss $A $b] a0 a1 a2 b0 b1 b2 c0 c1

set ::H [subst {
    {$a0 $a1 $a2}
    {$b0 $b1 $b2}
    {$c0 $c1 1}
}]

proc cameraToProjector {cameraPoint} {
    lassign [math::linearalgebra::matmul $::H [list [lindex $cameraPoint 0] [lindex $cameraPoint 1] 1]] Hx Hy Hz
    set Hx [expr $Hx / $Hz]
    set Hy [expr $Hy / $Hz]
    return [list $Hx $Hy]
}

proc testPoint {i} {
    upvar points points
    puts "(x$i, y$i) = ([lindex $points $i 0], [lindex $points $i 1])"
    puts "(u$i, v$i) = ([lindex $points $i 2], [lindex $points $i 3])"
    lassign [cameraToProjector [lindex $points $i]] Hx Hy
    puts "H(x$i, y$i) = ($Hx, $Hy)"
}
testPoint 0
puts ""
testPoint 1