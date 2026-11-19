#shellcheck disable=SC2034,SC1090,SC2004 # globals are shared with the other files, and the state file is sourced

#check OS
OS=${SW_OS:-$(uname -s)}

#alert limits ni percent
WARN_CPU=90 WARN_MEM=90 WARN_DISK=90 EVERY=2 LOG=$HOME/.serverwatch.log WEBHOOK=${WEBHOOK:-}

#check some stuff so our bash thing actually works
CHECKS=()

CPU=0 MEM=0 MEMU=0 MEMT=1 RX=0 TX=0 LOAD="" UPT=""
DISKS=() PROCS=() PORTS=() CHK=() ALERTS=() ONK=()
H_CPU=() H_MEM=() H_RX=() H_TX=() 
GEN=0 PT=0 PR=0 PX=0 BASED=0 ONCE=0

declare -A ON=() N=() BASE=()

#i really like conky for linux, so im gonna show CPU busy percent

get_cpu() {
    local l x=""
    if [[ $OS == Darwin ]]; then
        #macOS
        while read -r l; do [[ $l == *"CPU usage"* ]] && x=$l; done < <(top -l 2 -n 0 -s 1)
    else
        #linux
        while read -r l; do [[ $l == *"Cpu(s)"* ]] && x=$l; done < <(top -bn2 -d1)
    fi

    #cut random stuff
    x=${x%%id*}; x=${x##*,}; x=${x//[^0-9.]/}
    #DECIMALS BEGONE
    x=${x%%.*}
    
    #no number counts as fully idle
    CPU=$(( 100 - ${x:-100} ))
}

#like conky once again, we gona do memory usage

get_mem() {
    local k v
    local -A m=()
    if [[ $OS == Darwin ]]; then
    #theres still a bunch of jargon so
        while IFS=: read -r k v; do m[$k]=${v//[^0-9]/}; done < <(vm_stat)
        MEMT=$(( $(sysctl -n hw.memsize) / 1024))
        MEMU=$(( (${m[Anonymous pages]} - ${m[Pages purgeable]} + ${m[Pages wired down]} + ${m[Pages occupied by compressor]}) * ${m[Mach Virtual Memory Statistics]} / 1024 ))
    else
        while read -r k v _; do
            case $k in
                MemTotal:) MEMT=$v ;;
                MemAvailable:) MEMU=$(( MEMT - v )) ;;
            esac
        done </proc/meminfo
    fi
    MEM=$(( MEMU * 100 / MEMT ))
}

#download and upload speed in bytes per second
get_net() {
    local -a f
    local n i w r=0 x=0 t=${EPOCHREALTIME/./} ib=-5 ob=-2
    if [[ $OS == Darwin ]]; then
        while read -r -a f; do
            if [[ ${f[0]} == Name ]]; then
                for (( i = 0; i < ${#f[@]}; i++ )); do
                    [[ ${f[i]} == Ibytes ]] && ib=$(( i - ${#f[@]} ))
                    [[ ${f[i]} == Obytes ]] && ob=$(( i - ${#f[@]} ))
                    done
                fi
                [[ ${f[2]} == '<Link#'* && ${f[0]} == en* ]] && (( r += f[ib], x += f[ob] ))
        done < <(netstat -ib)
    else
        while IFS=': ' read -r n i _ _ _ _ _ _ _ w _; do
            [[ $n == lo || $n == veth* || $n == docker* || $n == br-* || ! $i =~ ^[0-9]+$ ]] || (( r += i, x += w ))
        done </proc/net/dev
    fi

    #speed
    (( PT )) && { RX=$(( (r - PR) * 1000000 / (t - PT) )); TX=$(( (x - PX) * 1000000 / (t - PT) )); }
    #counter 
    (( RX < 0 )) && RX=0
    (( TX < 0 )) && TX=0

    PT=$t PR=$r PX=$x
}

# load average and uptime
get_load() {
    local x
    x=$(uptime)
    LOAD=${x#*load average}; LOAD=${LOAD#*: }; LOAD=${LOAD//,/}
    UPT=${x#*up }; UPT=${UPT%,*user*}
}

#one entry per disk
get_disks() {
    local fs sz us av pc mp
    DISKS=()
    while read -r fs sz us av pc mp; do
        [[ $fs == /dev/* && $fs != /dev/loop* ]] || continue
        case $mp in /System/Volumes/[VPUxiH]*|/snap/*) continue ;; esac
        DISKS+=("$mp|${pc%\%}")
    done < <(df -Pk)
}

#20 busiest processes
get_procs() {
    local p c m n
    PROCS=()
    while read -r p c m n; do
        PROCS+=("$p|$c|$m|${n##*/}")
    done < <(ps -Ao pid=,pcpu=,pmem=,comm= | sort -k2 -nr | head -n 20)
}

#listening TCP ports
get_ports() {
    local -a w
    local a b c d e f n p
    mapfile -t PORTS < <(
        if [[ $OS == Darwin ]]; then
            lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null | while read -r -a w; do
                n=${w[-2]}
                [[ $n == *:* ]] && echo "${n##*:}|${n%:*}|${w[0]}"
            done
        else
            ss -tlnp 2>/dev/null | while read -r a b c d e f; do
                p=${f#*\"}
                [[ $a == LISTEN ]] && echo "${d##*:}|${d%:*}|${p%%\"*}"
            done
        fi | sort -t'|' -k1,1n -u
    )
}

#run every CHECKS entry
get_checks() {
    local c k n a b t s i p
    CHK=()
    for c in "${CHECKS[@]}"; do
        read -r k n a b <<<"$c"
    t=${EPOCHREALTIME/./} s=down
    case $k in
        tcp)
            ( exec 3<>"/dev/tcp/$a/$b" ) 2>/dev/null &
            p=$!
            for (( i = 0; i < 100; i ++ )); do kill -0 "$p" 2>/dev/null || break; sleep 0.02; done
            kill "$p" 2>/dev/null
            wait "$p" 2>/dev/null && s=up
            ;;
        http)
            [[ $(curl -s -o /dev/null -m 2 -w '%{http_code}' "$a") == [23]* ]] && s=up
            ;;
        esac
        CHK+=("$n|$s|$(( (${EPOCHREALTIME/./} - t) / 1000 ))")
    done
}

notify() {
    local m=${1//[\"\\]/} t
    printf -v t '%(%H:%M:%S)T' -1
    ALERTS+=("$t $1")
    (( ${#ALERTS[@]} > 50 )) && ALERTS=("${ALERTS[@]:1}")
    echo "$t $1"
    (( ONCE )) && return
    printf '%(%F %T)T %s\n' -1 "$1" >>"$LOG"
    [[ -n $WEBHOOK ]] && curl -s -m 5 -H 'Content-Type: application/json' -d "{\"content\":\"$HOST: $m\"}" "$WEBHOOK" >/dev/null 2>&1 &
    [[ $OS == Darwin ]] && osascript -e "display notification \"$m\" with title \"ServerWatch Alert\"" >/dev/null 2>&1 &
}

alert() {
    if (( $2 )); then
        (( ++N["$1"] >= 2 - ONCE )) && [[ -z ${ON[$1]-} ]] && { ON[$1]=1; notify "ALERT $3"; }
    else
        N["$1"]=0
        [[ -n ${ON[$1]-} ]] && { unset 'ON[$1]'; notify "OK ${1/:/ } back to normal"; }
    fi
}

judge() {
    local s m p n st a pr k
    local -A cur=()
    alert cpu $(( CPU >= WARN_CPU )) "cpu at $CPU%"
    alert mem $(( MEM >= WARN_MEM )) "mem at $MEM%"

    for s in "${DISKS[@]}"; do
        IFS='|' read -r m p <<<"$s"
        alert "disk:$m" $(( p >= WARN_DISK )) "disk $m at $p%"
    done    
    #one rule per check [[ ]] 
    for s in "${CHK[@]}"; do
        IFS='|' read -r n st _ <<<"$s"
        [[ $st == down ]]
        alert "check:$n" $(( ! $? )) "$n is down"
    done

    for s in "${PORTS[@]}"; do
        IFS='|' read -r p a pr <<<"$s"
        cur[$p]=1
        if (( BASED )); then alert "listen:$p" $(( ${BASE[$p]-0} == 0 )) "new listener : $p ${pr:-unknown}"; else BASE[$p]=1; fi
    done
    BASED=1
    for k in "${!ON[@]}"; do
        [[ $k == listen:* && -z ${cur[${k#listen:}]-} ]] && alert "$k" 0
    done
}

hist() {
    local -n h=$1
    h+=("$2")
    (( ${#h[@]} > 60 )) && h=("${h[@]:1}")
}

dump() {
    local k
    for k; do declare -p "$k"; done | while read -r _ _ k; do echo "$k"; done
}

sw_loop() {
    while :; do
        get_cpu; get_mem; get_net; get_load; get_disks; get_procs; get_ports; get_checks;
        hist H_CPU "$CPU"; hist H_MEM "$MEM"; hist H_RX "$RX"; hist H_TX "$TX"
        judge
        ONK=("${!ON[@]}")
        GEN=$(( GEN + 1 ))
        dump GEN CPU MEM MEMU MEMT RX TX LOAD UPT H_CPU H_MEM H_RX H_TX DISKS PROCS PORTS CHK ALERTS ONK >"$STATE.tmp"
        mv -f "$STATE.tmp" "$STATE"
        (( ONCE )) && return
        kill -0 "$PARENT" 2>/dev/null || return
        sleep "$EVERY"
    done
}

