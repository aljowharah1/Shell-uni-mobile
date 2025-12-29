{
    if ($1 != prev1 || $2 != prev2) {
        print NR, $1, $2
        count++
    }
    prev1=$1
    prev2=$2
}
END {
    print "Total unique positions:", count
}