export PATH=/opt/bin:/opt/sbin:$PATH

if [ -t 1 ] && [ -x /opt/bin/zsh ] && [ -z "$ZSH_VERSION" ]; then exec /opt/bin/zsh -l; fi
umask 022