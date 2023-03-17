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
vwait good

Assert when we are running {
    On process {
        set n 0
        while true {
            incr n
            Commit { Claim the counter is $n }
            Step
        }
    }

    When the counter is /n/ {
        puts $n
    }
}
Step
vwait done
