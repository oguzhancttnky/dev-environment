function _fzf_search_history --description "Search command history."

    if test -z "$fish_private_mode"
        builtin history merge
    end

    if not set -q fzf_history_time_format
        set -g fzf_history_time_format "%m-%d %H:%M:%S"
    end

    set -l time_prefix_regex '^.*? │ '

    set -l commands_selected (
        builtin history --null --show-time="$fzf_history_time_format │ " |
        fzf --read0 \
            --print0 \
            --multi \
            --prompt="History> " \
            --query=(commandline) \
            --preview="string replace --regex '$time_prefix_regex' '' -- {} | fish_indent --ansi" \
            --preview-window="bottom:3:wrap" \
            --bind="ctrl-r:execute(echo {q})+abort" \
            $fzf_history_opts |
        string split0 |
        string replace --regex $time_prefix_regex ''
    )

    if test $status -eq 0
        commandline --replace -- $commands_selected
    end

    commandline --function repaint
end

bind \cr '_fzf_search_history'