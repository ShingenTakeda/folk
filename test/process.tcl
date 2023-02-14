Assert when we are running {
    On process A {
        puts hello
    }
}
Assert we are running
Step

Assert when we are running {
    On process {
        Assert things are good
        Step
    }

    When things are good {
        set ::good true
    }
}
Step

after 500 {
    if {[info exists ::good] && $::good} { exit 0 } \
        else { exit 1 }
}
vwait forever
