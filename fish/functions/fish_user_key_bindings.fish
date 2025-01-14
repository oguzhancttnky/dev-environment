function _fzf_search_history
    history | fzf --height=40% --reverse | read -l command
    if test -n "$command"
        commandline -r $command
    end
end

bind \cr '_fzf_search_history'