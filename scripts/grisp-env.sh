# Source this in an interactive shell to select the SDK and configure its
# target C and Erlang/NIF build environment. Build scripts use cross-env.sh
# and project-env.sh to create command-scoped environments instead.

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    echo "ERROR: the script grisp-env.sh must be sourced" >&2
    exit 1
fi

source "$(dirname "${BASH_SOURCE[0]}")/cross-env.sh" "${1:-}" || return $?
source "$(dirname "${BASH_SOURCE[0]}")/project-env.sh" || return $?
project_env_erlang || return $?

echo "*************************************************"
echo "*** CROSS-COMPILATION ENVIRONMENT INITIALIZED ***"
echo "*************************************************"
echo " Grisp Target:   $GLB_TARGET_NAME"
echo " Target Arch:    $CROSSCOMPILE_ARCH"
echo " Common Version: $GLB_COMMON_SYSTEM_VER"
echo " Target Version: $GLB_TARGET_SYSTEM_VER"
echo "*************************************************"
echo

PROMPT_POSTFIX="[$GLB_TARGET_NAME sdk]"
if [[ ${PS1:-} != *"${PROMPT_POSTFIX} " ]]; then
	PS1="${PS1:-}${PROMPT_POSTFIX} "
fi

return 0
