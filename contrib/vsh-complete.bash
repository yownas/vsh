# Autocompletion of vsh clients
#
# source this file or add content to your .bashrc

_vsh() 
{
    local cur prev opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    opts=$(cat ~/.vsh/var/ctstate | cut -d ' ' -f 2)

    COMPREPLY=( $(compgen -W "$opts" -- ${cur}) )
    return 0
}
complete -F _vsh vsh
