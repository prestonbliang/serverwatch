# shellcheck disable=SC2034  # globals are shared with the other files#globals r shared with other files

ROWS=24
COLS=80
RESIZED=0
TTY_ON=0
STTY_SAVED=""

term_size() {
    size=$(stty size 2>/dev/null) || return 1
    rows=${size% *}
    cols=${size#* }
    #some of th nasty ptys report 0x0 
    (( rows > 0 && cols > 0 )) || return 1
    ROWS=$rows COLS=$cols
}
#AYO SSSSUSUSUUSUSUSU
term_init() {
    ((TTY_ON)) && return 0
    STTY_SAVED=$(stty -g) || return 1
    stty -echo -icanon -ixon
    #alt screeeeeeeeen, hide cursor and mouse plus drag & SGR encoding!!
    printf '\e[?1049h\e[?25l\e[?1000h\e[?1002h\e[?1006h\e[2J'
    TTY_ON=1
    term_size
    trap 'RESIZED=1' WINCH
}

term_restore() {
    ((TTY_ON)) || return 0
    printf '\e[?1006l\e[?1002l\e[?1000l\e[?25h\e[?1049l'
    stty "$STTY_SAVED"
    TTY_ON=0
}