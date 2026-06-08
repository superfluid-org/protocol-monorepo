# Keystore password file for Foundry signing (cast send / forge --account).
# Do not export ETH_PASSWORD globally — it breaks read-only `cast call`.
#
#   KEYSTORE_PASSWORD       — inline password (→ temp file); empty string is valid
#   KEYSTORE_PASSWORD_FILE  — path to password file
#   SF_KEYSTORE_PASSWORD_FILE — password file path; signing wrappers pass ETH_PASSWORD per command

_keystore_password_cleanup() {
    if [[ -n "${_KEYSTORE_PASSWORD_TMP:-}" && -f "${_KEYSTORE_PASSWORD_TMP}" ]]; then
        rm -f "$_KEYSTORE_PASSWORD_TMP"
        unset _KEYSTORE_PASSWORD_TMP
    fi
}

apply_keystore_password_env() {
    [[ -n "${_KEYSTORE_ENV_APPLIED:-}" ]] && return 0

    if [[ -n "${SF_KEYSTORE_PASSWORD_FILE:-}" ]]; then
        _KEYSTORE_ENV_APPLIED=1
        return 0
    fi

    if [[ -n "${ETH_PASSWORD:-}" ]]; then
        SF_KEYSTORE_PASSWORD_FILE="$ETH_PASSWORD"
        unset ETH_PASSWORD
        export SF_KEYSTORE_PASSWORD_FILE
        _KEYSTORE_ENV_APPLIED=1
        return 0
    fi

    if [[ -n "${KEYSTORE_PASSWORD_FILE:-}" ]]; then
        if [[ ! -f "${KEYSTORE_PASSWORD_FILE}" ]]; then
            echo "KEYSTORE_PASSWORD_FILE not found: ${KEYSTORE_PASSWORD_FILE}" >&2
            return 1
        fi
        SF_KEYSTORE_PASSWORD_FILE="$KEYSTORE_PASSWORD_FILE"
        export SF_KEYSTORE_PASSWORD_FILE
        _KEYSTORE_ENV_APPLIED=1
        return 0
    fi

    if [[ -v KEYSTORE_PASSWORD ]]; then
        _KEYSTORE_PASSWORD_TMP=$(mktemp)
        chmod 600 "$_KEYSTORE_PASSWORD_TMP"
        printf '%s' "$KEYSTORE_PASSWORD" > "$_KEYSTORE_PASSWORD_TMP"
        SF_KEYSTORE_PASSWORD_FILE="$_KEYSTORE_PASSWORD_TMP"
        export SF_KEYSTORE_PASSWORD_FILE
        trap _keystore_password_cleanup EXIT
        _KEYSTORE_ENV_APPLIED=1
        return 0
    fi

    _KEYSTORE_ENV_APPLIED=1
    return 0
}

# Run a command with ETH_PASSWORD scoped to this invocation only (signing commands).
with_keystore_password() {
    if [[ -n "${SF_KEYSTORE_PASSWORD_FILE:-}" ]]; then
        env ETH_PASSWORD="$SF_KEYSTORE_PASSWORD_FILE" "$@"
    else
        "$@"
    fi
}

# Wrappers — always use these instead of bare cast/forge for signing.
# They ensure the keystore password is passed without leaking ETH_PASSWORD globally.
cast_send_account() {
    local account=$1; shift
    with_keystore_password cast send --account "$account" "$@"
}

cast_wallet_address_account() {
    local account=$1; shift
    with_keystore_password cast wallet address --account "$account" "$@"
}

apply_keystore_password_env || exit 1
