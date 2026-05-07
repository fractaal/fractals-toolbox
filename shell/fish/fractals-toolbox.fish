# Fish entry point — the deploy installer symlinks this into ~/.config/fish/conf.d/.
# Sources fractals-toolbox fish modules in dependency order.
# Autospawn is sourced last because it execs tmux (replacing the shell process).

set -l fractal_fish_dir "$HOME/.fractals-toolbox/shell/fish"

if test -r "$fractal_fish_dir/tls.fish"
    source "$fractal_fish_dir/tls.fish"
end

if test -r "$fractal_fish_dir/tmux-autospawn.fish"
    source "$fractal_fish_dir/tmux-autospawn.fish"
end
