# Fish entry point — the deploy installer symlinks this into ~/.config/fish/conf.d/.
# Sources fractals-toolbox fish modules in dependency order.
# Autospawn is sourced last because it execs tmux (replacing the shell process).

# Prepend toolbox common/bin so wrapper scripts (e.g. qmd serializer) shadow their originals on PATH.
# -gP keeps this scoped to the current fish session's PATH (not written to universal fish_user_paths,
# which would persist forever even after uninstall). conf.d re-sources this file every interactive shell.
fish_add_path -gP -p "$HOME/.fractals-toolbox/common/bin"

set -l fractal_fish_dir "$HOME/.fractals-toolbox/shell/fish"

if test -r "$fractal_fish_dir/tls.fish"
    source "$fractal_fish_dir/tls.fish"
end

if test -r "$fractal_fish_dir/tjoin.fish"
    source "$fractal_fish_dir/tjoin.fish"
end

if test -r "$fractal_fish_dir/tmux-autospawn.fish"
    source "$fractal_fish_dir/tmux-autospawn.fish"
end
