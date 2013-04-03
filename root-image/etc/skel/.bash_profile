# System settings before starting X
. $HOME/.bashrc

# set up alsa
/usr/bin/amixer sset Master Mono 90% unmute
/usr/bin/amixer sset Master 90% unmute
/usr/bin/amixer sset PCM 90% unmute

# Do not add anything after next line
[[ $(fgconsole 2>/dev/null) == 1 ]] && exec startx -- vt1


