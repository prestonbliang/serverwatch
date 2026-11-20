# shellcheck disable=SC2034,SC1090,SC2004 # globals are shared with the other files, and the state file is sourced

#CLOCK
CLOCK=""
#color code
S=32


#text, cut tho
txt() {
    put "$1" "$2" "${4:0:$3}" "${5:-}"
}

#panel
panel() {
    box "$1" "$2" "$3" "$4" 2
    put "$1" $(( $2 + 2 )) " $5 " "1;36"
}

#percent bar
bar() {
    local f=$(( $1 * 10 / 100 )) e
    (( f > 10 )) && f=10

    printf -v REPLY '%*s' "$f" ''
    REPLY=${REPLY// /$'\u2588'}
    printf -v e '%*s' $(( 10 - f )) ''
    REPLY+=${e// /$'\u2591'} 
    S=$(( $1 < 70 ? 32 : $1 < 90 ? 33 : 31 ))
}

bytes() {
    local n=$(( $1 * 10 )) i=0 u=BKMGT
    while (( n >= 10240 )); do n=$(( n / 1024 )); i=$(( i + 1 )); done
    REPLY="$(( n / 10 )).$(( n % 10 ))${u:i:1}"
}

spark() {
    local -n h=$1
    local n=${#h[@]} i s=$'\u2581\u2582\u2583\u2584\u2585\u2586\u2587\u2588' v m=$3 out=""

    if (( m == 0 )); then
        m=10240
        for v in "${h[@]}"; do (( v > m )) && m=$v; done
    fi

    for (( i = n > $2 ? n - $2 : 0; i < n; i++ )); do
        v=$(( h[i] * 7 / m ))
        (( v > 7 )) && v=7
        out+=${s:v:1}
    done
    printf -v REPLY '%*s' $(( $2 - ${#out} )) ''
    REPLY+="$out"
}

meter() {
    put "$1" 3 "$2" 1 
    
    if [[ -n ${6-} ]]; then bar "$6"; put "$1" 8 "$REPLY" "$S"; else S=36; fi

    put "$1" 19 "$3" "$S"
    spark "$4" $(( l - 29 )) "$5"
    put "$1" 28 "$REPLY" 36
}

draw() {
    local l=$(( COLS * 11 / 20 )) r b c i s t p m n a pr k
    r=$(( COLS - l )) c=$(( (ROWS - 9) / 2 ))
    b=$(( ROWS - 9 - c ))
    
    clear_screen

    if (( ROWS < 18 || COLS < 60 )); then
        center $(( ROWS / 2 )) "Terminal too small"
        flush 
        return
    fi
    #top
    fill 1 1 1 "$COLS" " " 7
    put 1 1 " serverwatch $HOST $OS up $UPT  load $LOAD" 7
    put 1 $(( COLS - 9 )) "$CLOCK " 7
    (( ${#ONK[@]} )) && put 1 $(( COLS - 20 )) " ${#ONK[@]} ALERT " "1;37;41"
    #bottom
    fill "$ROWS" 1 1 "$COLS" " " 7
    put "$ROWS" 1 " q quit     every ${EVERY}s     config ~/.serverwatch.conf     log ~/.serverwatch.log" 7
     if (( ! GEN )); then
        center $(( ROWS / 2 )) "collecting the first readings..." 36
        flush
        return
    fi
    # resources: four meters and a summary line
    panel 2 1 7 "$l" resources
    meter 3 cpu "$CPU%" H_CPU 100 "$CPU"
    meter 4 mem "$MEM%" H_MEM 100 "$MEM"
    bytes "$RX"; meter 5 down "$REPLY/s" H_RX 0
    bytes "$TX"; meter 6 up "$REPLY/s" H_TX 0
    bytes $(( MEMU * 1024 )); t=$REPLY
    bytes $(( MEMT * 1024 ))
    put 7 3 "memory $t of $REPLY" 2
    # disks: name, bar, percent
    panel 2 $(( l + 1 )) 7 "$r" disks
    i=3
    for s in "${DISKS[@]}"; do
        (( i < 8 )) || break
        IFS='|' read -r m p <<<"$s"
        # show the last part of the path, or / for the root
        [[ $m == / ]] || m=${m##*/}
        txt "$i" $(( l + 3 )) 10 "$m" 1
        bar "$p"
        put "$i" $(( l + 14 )) "$REPLY" "$S"
        printf -v t '%3d%%' "$p"
        put "$i" $(( l + 25 )) "$t" "$S"
        i=$(( i + 1 ))
    done
    # processes
    panel 9 1 "$b" "$l" processes
    put 10 3 "   PID   CPU%   MEM%  NAME" 1
    i=11
    for s in "${PROCS[@]}"; do
        (( i <= b + 7 )) || break
        IFS='|' read -r p k m n <<<"$s"
        printf -v t '%6s %6s %6s  %s' "$p" "$k" "$m" "$n"
        txt "$i" 3 $(( l - 4 )) "$t"
        i=$(( i + 1 ))
    done
    # listening ports: yellow when open to the network, dim when only this machine can reach it, red when new
    panel 9 $(( l + 1 )) "$b" "$r" "listening ports"
    put 10 $(( l + 3 )) "PORT   ADDRESS         PROGRAM" 1
    i=11
    for s in "${PORTS[@]}"; do
        (( i <= b + 7 )) || break
        IFS='|' read -r p a pr <<<"$s"
        printf -v t '%-6s %-15s %s' "$p" "${a:0:15}" "$pr"
        case $a in 127.*|::1|\[::1\]) k=2 ;; *) k=33 ;; esac
        # a port with an active "new listener" alert
        if [[ " ${ONK[*]} " == *" listen:$p "* ]]; then t+=" NEW"; k="1;31"; fi
        txt "$i" $(( l + 3 )) $(( r - 4 )) "$t" "$k"
        i=$(( i + 1 ))
    done
    # checks from the config file
    panel $(( 9 + b )) 1 "$c" "$l" checks
    i=$(( 10 + b ))
    (( ${#CHK[@]} )) || txt "$i" 3 $(( l - 4 )) "none yet. add tcp and http lines to CHECKS in the config file" 2
    for s in "${CHK[@]}"; do
        (( i <= b + c + 7 )) || break
        IFS='|' read -r n m p <<<"$s"
        printf -v t '%-16s %-5s %5sms' "${n:0:16}" "${m^^}" "$p"
        [[ $m == up ]] && k=32 || k="1;31"
        txt "$i" 3 $(( l - 4 )) "$t" "$k"
        i=$(( i + 1 ))
    done
    # alert history, newest first
    panel $(( 9 + b )) $(( l + 1 )) "$c" "$r" alerts
    i=$(( 10 + b ))
    (( ${#ALERTS[@]} )) || txt "$i" $(( l + 3 )) $(( r - 4 )) "all clear" 32
    for (( k = ${#ALERTS[@]} - 1; k >= 0 && i <= b + c + 7; k--, i++ )); do
        s=${ALERTS[k]}
        [[ $s == *" ALERT "* ]] && p="1;31" || p=32
        txt "$i" $(( l + 3 )) $(( r - 4 )) "$s" "$p"
    done
    # send the changes to the terminal
    flush
}

# q (or ctrl-c) quits. every other key does nothing
on_key() {
    case $IN_KEY in q|ctrl-c|ctrl-q) QUIT=1 ;; esac
}

# nothing special to do on resize, the loop redraws by itself
on_resize() {
    :
}

# once a second: update the clock and read the newest saved readings
on_tick() {
    local t
    printf -v t '%(%H:%M:%S)T' -1
    # still the same second
    [[ $t == "$CLOCK" ]] && return
    CLOCK=$t
    DIRTY=1
    # load what the collector saved (it contains plain assignments like CPU="12")
    source "$STATE"
}