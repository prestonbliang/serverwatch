# shellcheck disable=SC2034  # globals are shared with the other files
#input handlers for keyboard and mouse input, including SGR mouse support

IN_KEY="" IN_ACT="" IN_BTN="" IN_X=0 IN_Y=0

poll_input() {
    local c rc ord letters=abcdefghijklmnopqrstuvwxyz
    IN_KEY=""
    IFS= read -rsn1 -t "${1:-0.05}" c
    rc=$?
    (( rc > 128 )) && return 1
    (( rc )) && return 2
    
    case $c in
      ''|$'\r')       IN_KEY=enter ;;
      $'\t')          IN_KEY=tab ;;
      $'\177'|$'\b')  IN_KEY=backspace ;;
      ' ')            IN_KEY=space ;;
      $'\e')          read_escape ;;
      *)
        printf -v ord '%d' "'$c"
        if (( ord >= 1 && ord <= 26 )); then
          IN_KEY=ctrl-${letters:ord-1:1}
        else
          IN_KEY=$c
        fi
        ;;
    esac
    return 0
}
  
  #esc KEY, kinda confuzzling
read_escape() {
    local c seq="" ord
    if ! IFS= read -rsn1 -t 0.01 c; then
        IN_KEY=esc
        return
    fi
    if [[ $c != '[' && $c != "O" ]]; then
        IN_KEY=esc
        return
    fi

    #sequences end on a byte in @..~
    while IFS= read -rsn1 -t 0.01 c; do
        seq+=$c
        printf -v ord '%d' "'$c"
        (( ord >= 64 && ord <= 126 )) && break
    done

    if [[ $seq == '<'*[Mm] ]]; then
        parse_mouse "$seq"
    else
        parse_csi "$seq"
    fi
}

#SGR MOUSE <btn;x;yM for press/drag/wheel, <btn;x;ym for release
parse_mouse() {
    local seq=$1 final=${1: -1} body rest b
    body=${seq:1:${#seq}-2}
    b=${body%%;*}
    rest=${body#*;}
    IN_X=${rest%%;*}
    IN_Y=${rest#*;}
    IN_KEY=mouse

    case $(( b & 3 )) in
        0) IN_BTN=left ;;
        1) IN_BTN=middle ;;
        2) IN_BTN=right ;;
        *) IN_BTN=none ;;
    esac

    if (( b & 64 )); then
        IN_BTN=none
        if (( b & 1 )); then IN_ACT=wheel-down; else IN_ACT=wheel-up; fi
    elif (( b & 32 )); then
        IN_ACT=drag
    elif [[ $final == m ]]; then
        IN_ACT=release
    else
        IN_ACT=press
    fi
}


# Other ESC [ / ESC O sequences: "A", "1;5C", "3~". The modifier after the
# semicolon is 1 + a bitmask of shift=1, alt=2, ctrl=4.

parse_csi() {
    local seq=$1 final=${1: -1} params=${1%?} mod="" name
    if [[ $params == *';'* ]]; then
        case $((${params##*;} - 1)) in
            1) mod=shift- ;;
            2) mod=alt- ;;
            3) mod=alt-shift- ;;
            4) mod=ctrl- ;;
            5) mod=ctrl-shift- ;;
            6) mod=ctrl-alt- ;;
        esac
        params=${params%%;*}
    fi

    case $final in 
        'A') name=up ;;
        'B') name=down ;;
        'C') name=right ;;
        'D') name=left ;;
        'H') name=home ;;
        'F') name=end ;;
        'P') name=f1 ;;
        'Q') name=f2 ;;
        'R') name=f3 ;;
        'S') name=f4 ;;
        '~')
            case $params in
                1|7) name=home ;;
                3) name=delete ;;
                4|8) name=end ;;
                5) name=page-up ;;
                6) name=page-down ;;
                *) name=csi-$seq ;;
            esac
            ;;
        *) name=csi-$seq ;;
    esac
    IN_KEY=$mod$name
}