# shellcheck disable=SC2034  # globals are shared with the other files
#draw only runs when someting set DIRTY=1

QUIT=0
DIRTY=1
TICK=0.05

main_loop() {
    local rc
    while (( ! QUIT )); do
        if (( RESIZED )); then
            RESIZED=0
            term_size
            render_init
            on_resize
            DIRTY=1
        fi
        if (( DIRTY )) && ! read -r -t 0; then            DIRTY=0
            draw
        fi

        poll_input "$TICK"
        rc=$?
        (( rc == 0 )) && on_key
        (( rc == 2 )) && QUIT=1
        on_tick
    done
}