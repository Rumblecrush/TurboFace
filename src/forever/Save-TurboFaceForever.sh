#!/usr/bin/env bash
set -euo pipefail

wtf_root=""
account_file=""
character_file=""
assume_yes=false

usage() {
    cat <<'EOF'
Usage: ./Save-TurboFaceForever.sh [options]

Options:
  --wtf-root PATH       Full path to the Forever client's WTF directory
  --account-file PATH   Explicit account-wide TurboFace SavedVariables file
  --character-file PATH Explicit character TurboFace SavedVariables file
  --yes                 Skip the interactive SAVE confirmation
  -h, --help            Show this help
EOF
}

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

while (($#)); do
    case "$1" in
        --wtf-root)
            (($# >= 2)) || fail "--wtf-root requires a path"
            wtf_root=$2
            shift 2
            ;;
        --account-file)
            (($# >= 2)) || fail "--account-file requires a path"
            account_file=$2
            shift 2
            ;;
        --character-file)
            (($# >= 2)) || fail "--character-file requires a path"
            character_file=$2
            shift 2
            ;;
        --yes)
            assume_yes=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            fail "Unknown option: $1"
            ;;
    esac
done

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
addon_dir=$script_dir
addon_folder=$(basename -- "$addon_dir")
restore_file="$addon_dir/Core/ForeverRestoreData.lua"

if [[ $addon_dir == */.local/share/Trash/* ]]; then
    fail "This shell is still inside a deleted addon under Linux Trash. cd into the newly installed Interface/AddOns/TurboFace directory and run the saver there."
fi

if [[ -z $wtf_root ]]; then
    # Installed layout:
    # <client>/Interface/AddOns/TurboFaceForever/this-script.sh
    addons_dir=$(dirname -- "$addon_dir")
    interface_dir=$(dirname -- "$addons_dir")
    client_dir=$(dirname -- "$interface_dir")
    if [[ -d $client_dir/WTF ]]; then
        wtf_root=$client_dir/WTF
    fi
fi

[[ -n $wtf_root ]] || fail "Could not infer WTF. Pass --wtf-root with the _classic_beta_/WTF path."
[[ -d $wtf_root ]] || fail "WTF directory does not exist: $wtf_root"
wtf_root=$(cd -- "$wtf_root" && pwd)
account_root=$wtf_root/Account
[[ -d $account_root ]] || fail "No Account directory exists under: $wtf_root"

account_candidates=()
character_candidates=()
while IFS= read -r -d '' file; do
    relative=${file#"$account_root"/}
    IFS='/' read -r -a parts <<< "$relative"
    # Account/<ACCOUNT>/SavedVariables/<addon>.lua
    if ((${#parts[@]} == 3)) && [[ ${parts[1]} == SavedVariables ]]; then
        account_candidates+=("$file")
    # Account/<ACCOUNT>/<REALM OR NUMERIC ID>/<CHARACTER>/SavedVariables/<addon>.lua
    elif ((${#parts[@]} == 5)) && [[ ${parts[3]} == SavedVariables ]]; then
        character_candidates+=("$file")
    fi
done < <(find "$account_root" -type f \( \
    -name 'TurboFace.lua' -o \
    -name 'TurboFaceForever.lua' -o \
    -name "$addon_folder.lua" \
\) -print0)

newest_file() {
    local newest="" newest_time=-1 file modified
    for file in "$@"; do
        modified=$(stat -c '%Y' -- "$file")
        if ((modified > newest_time)); then
            newest=$file
            newest_time=$modified
        fi
    done
    printf '%s' "$newest"
}

if [[ -n $account_file ]]; then
    [[ -f $account_file ]] || fail "Account file does not exist: $account_file"
    account_source=$(realpath -- "$account_file")
else
    ((${#account_candidates[@]} > 0)) || fail "No account-wide TurboFace SavedVariables file was found."
    account_source=$(newest_file "${account_candidates[@]}")
fi

if [[ -n $character_file ]]; then
    [[ -f $character_file ]] || fail "Character file does not exist: $character_file"
    character_source=$(realpath -- "$character_file")
else
    ((${#character_candidates[@]} > 0)) || fail "No character TurboFace SavedVariables file was found."
    character_source=$(newest_file "${character_candidates[@]}")
fi

[[ $account_source == "$account_root"/* ]] || fail "Account file is outside $account_root"
[[ $character_source == "$account_root"/* ]] || fail "Character file is outside $account_root"
account_relative=${account_source#"$account_root"/}
character_relative=${character_source#"$account_root"/}
account_key=${account_relative%%/*}
character_account_key=${character_relative%%/*}
[[ $account_key == "$character_account_key" ]] || fail \
    "Account and character files belong to different accounts: $account_key / $character_account_key"

grep -Eq '^[[:space:]]*TurboFaceDB[[:space:]]*=' "$account_source" || \
    fail "Account source does not assign TurboFaceDB: $account_source"
grep -Eq '^[[:space:]]*TurboFaceCharDB[[:space:]]*=' "$character_source" || \
    fail "Character source does not assign TurboFaceCharDB: $character_source"

account_bytes=$(stat -c '%s' -- "$account_source")
character_bytes=$(stat -c '%s' -- "$character_source")
printf '\033[36mTurboFace Forever restore snapshot\033[0m\n'
printf 'Account source  : %s\n' "$account_source"
printf '  Modified/bytes: %s / %s\n' "$(stat -c '%y' -- "$account_source")" "$account_bytes"
printf 'Character source: %s\n' "$character_source"
printf '  Modified/bytes: %s / %s\n' "$(stat -c '%y' -- "$character_source")" "$character_bytes"
printf 'Restore target  : %s\n\n' "$restore_file"
printf '\033[33mOnly continue if TurboFace was in a good state when you logged out.\033[0m\n'

if [[ $assume_yes != true ]]; then
    read -r -p 'Type SAVE to update the restore snapshot: ' confirmation
    if [[ $confirmation != SAVE ]]; then
        printf 'Cancelled; no files were changed.\n'
        exit 2
    fi
fi

backup_dir=$addon_dir/ForeverRestoreBackups
mkdir -p -- "$backup_dir"
if [[ -f $restore_file ]]; then
    backup_file=$backup_dir/ForeverRestoreData-$(date +%Y%m%d-%H%M%S).lua
    cp -- "$restore_file" "$backup_file"
    printf 'Previous snapshot: %s\n' "$backup_file"
fi

generated_at=$(date --iso-8601=seconds)
temp_file=$(mktemp "$restore_file.tmp.XXXXXX")
cleanup() { rm -f -- "$temp_file"; }
trap cleanup EXIT
{
    printf '%s\n' '-- GENERATED FILE -- DO NOT HAND EDIT'
    printf '%s\n' '-- Generated by Save-TurboFaceForever.sh after a deliberate logout.'
    printf '%s\n' "-- Account source: $account_source"
    printf '%s\n\n' "-- Character source: $character_source"
    cat -- "$account_source"
    printf '\n\n'
    cat -- "$character_source"
    printf '\n\nTurboFaceForeverRestoreMeta = {\n'
    printf '    enabled = true,\n'
    printf '    format = 1,\n'
    printf '    generatedAt = [==[%s]==],\n' "$generated_at"
    printf '    accountSource = [==[%s]==],\n' "$account_source"
    printf '    characterSource = [==[%s]==],\n' "$character_source"
    printf '    accountBytes = %s,\n' "$account_bytes"
    printf '    characterBytes = %s,\n' "$character_bytes"
    printf '}\n'
} > "$temp_file"
mv -f -- "$temp_file" "$restore_file"
trap - EXIT

printf '\n\033[32mSaved TurboFace restore snapshot successfully.\033[0m\n'
printf 'The next login or /reload will preload these settings and character data.\n'
