# shellcheck disable=SC2034  # WRAP_ROWS is read by desktop.sh
#collects frame in FRAMe and its GONA write it with a single printf

NEXT=() SHOWN=() BLANK=()
CLIP_ROW=24 CLIP_COL=80

case ${LC_ALL:-${LC_CTYPE:-${LANG:-}}} in
    *[Uu][Tt][Ff]-8*|*[Uu][Tt][Ff]8*) B_TL=┌ B_TR=┐ B_BL=└ B_BR=┘ B_H=─ B_V=│ ;;
    *) B_TL=+ B_TR=+ B_BL=+ B_BR=+ B_H=- B_V='|' ;;
esac

clip_reset() { CLIP_ROW=$ROWS CLIP_COL=$COLS; }

render_init() {
    local i
    BLANK=()
    for (( i = 0; i < ROWS * COLS; i++ )); do BLANK[i]="| "; done
        NEXT=("${BLANK[@]}")
        SHOWN=("${BLANK[@]/*/?}")
        clip_reset
        printf '\e[2J'
}

clear_screen() { NEXT=("${BLANK[@]}"); }
put() {
    local row=$1 col=$2 text=$3 sgr=${4:-} i
    (( row >= 1 && row <= CLIP_ROW )) || return 0
    for (( i = 0; i < ${#text}; i++, col++ )); do
        (( col >= 1 && col <= CLIP_COL )) || continue
        NEXT[(row - 1) * COLS + col - 1]="$sgr|${text:i:1}"
    done
}

fill() { 
    local r c ch=${5:- } sgr=${6:-} 
    for (( r = $1; r < $1 + $3; r++ )); do
        (( r >= 1 && r <= ROWS )) || continue
        for (( c = $2; c < $2 + $4; c++ )); do
            (( c >= 1 && c <= COLS )) || continue
            NEXT[(r - 1) * COLS + c - 1]="$sgr|$ch"
        done
    done

}

box() {
    local row=$1 col=$2 h=$3 w=$4 sgr=${5:-} r line
    (( w >= 4 && h >= 3 )) || return 0
    printf -v line '%*s' $(( w - 2 )) ''
    line=${line// /$B_H}
    put "$row" "$col" "$B_TL$line$B_TR" "$sgr"
    put $(( row + h - 1 )) "$col" "$B_BL$line$B_BR" "$sgr"
    for (( r = row + 1; r < row + h - 1; r++ )); do
        put "$r" "$col" "$B_V" "$sgr"
        put "$r" $(( col + w - 1 )) "$B_V" "$sgr"
    done

}


#CENTER ROW TEXT [SGR]

center() {
    local col=$(( (COLS - ${#2}) / 2 + 1 ))
    put "$1" $(( col < 1 ? 1 : col )) "$2" "${3:-}"
}

wrap() {
    local row=$1 col=$2 width=$3 sgr=${5:-} line="" word words
    read -ra words <<<"$4"
    for word in "${words[@]}"; do
        if [[ -n $line ]] && (( ${#line} + ${#word} + 1 > width )); then
            put "$row" "$col" "$line" "$sgr"
            (( row++ ))
            line="$word"
        else
            line="${line:+$line }$word"
        fi
    done
    [[ -n $line ]] && put "$row" "$col" "$line" "$sgr"
    WRAP_ROWS=$(( row - $1 + 1 ))

}

flush() {
    local IFS=$'\x1f'
    local out="" r c i start cell sgr cur="" last=-2
    for(( r = 0; r < ROWS; r++ )); do
        start=$(( r * COLS ))
        [[ ${NEXT[*]:start:COLS} == "${SHOWN[*]:start:COLS}" ]] && continue
        for(( c = 0; c < COLS; c++ )); do
            i=$(( start + c ))
            cell=${NEXT[i]}
            [[ $cell == "${SHOWN[i]}" ]] && continue
            SHOWN[i]=$cell
            (( c > 0 && i == last + 1 )) || out+=$'\e['"$(( r + 1 ));$(( c + 1 ))H"
            sgr=${cell%%|*}
            if [[ $sgr != "$cur" ]]; then
                out+=$'\e[0'"${sgr:+;$sgr}m"                cur=$sgr
            fi
            out+="${cell#*|}"
            last=$i
        done
    done
    [[ -n $out ]] && printf '%s\e[0m' "$out"
    return 0
}