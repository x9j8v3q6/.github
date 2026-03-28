#!/bin/bash

# ==============================================================================
# Script Name:  changelog-autogen.sh
# Description:  Automated "Keep a Changelog" generator based on Conventional Commits.
# ==============================================================================

# --- CONFIGURATION & DEFAULTS ---
VERSION_INPUT=""
RAW_COMMITS=""
FILE="CHANGELOG.md"
DATE=$(date +%Y-%m-%d)
PLACEHOLDER="---"

# Default Template Text
TITLE_TEXT="Changelog"
DESC_TEXT="All notable changes to this project will be documented in this file.\n\nThe format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),\nand this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html)."

usage() {
    printf "Usage: %s -v <version> -c <commits_string> [-d <date>] [-f <file>] [-t <title>] [-m <description>]\n" "$0"
    exit 1
}

# --- ARGUMENT PARSING ---
while getopts "v:c:d:f:t:m:h" opt; do
    case ${opt} in
        v ) VERSION_INPUT=$OPTARG ;;
        c ) RAW_COMMITS=$OPTARG ;;
        d ) DATE=$OPTARG ;;
        f ) FILE=$OPTARG ;;
        t ) TITLE_TEXT=$OPTARG ;;
        m ) DESC_TEXT=$OPTARG ;;
        * ) usage ;;
    esac
done

# Cleanup version string (remove 'v' prefix if present)
VERSION=$(echo "$VERSION_INPUT" | sed 's/^v//')
[[ -z "$VERSION" || -z "$RAW_COMMITS" ]] && usage

# --- VALIDATION ---
if [[ -f "$FILE" ]] && grep -qF -- "## [$VERSION]" "$FILE"; then
    printf "❌ Error: Version [%s] already exists in %s.\n" "$VERSION" "$FILE"
    exit 1
fi

# --- PARSING LOGIC ---
parse_commits() {
    echo "$RAW_COMMITS" | grep -Ei -e "$1" | while read -r line; do
        [[ -z "$line" ]] && continue
        # Strip Conventional Commit prefix (e.g., feat(scope):)
        CLEAN=$(echo "$line" | sed -E 's/^[a-z!]+\(?.*\)?\:[[:space:]]*//I')
        # Capitalize first letter
        FIRST=$(echo "${CLEAN:0:1}" | tr '[:lower:]' '[:upper:]')
        printf -- "- %s%s\n" "$FIRST" "${CLEAN:1}"
    done
}

# --- SECTION EXTRACTION ---
# Extraction of Breaking Changes (indicated by '!')
BREAKING=$(echo "$RAW_COMMITS" | grep -E -e "^[a-z]+\!:" | while read -r line; do
    CLEAN=$(echo "$line" | sed -E 's/^[a-z!]+\!?:[[:space:]]*//I')
    FIRST=$(echo "${CLEAN:0:1}" | tr '[:lower:]' '[:upper:]')
    printf -- "- %s%s\n" "$FIRST" "${CLEAN:1}"
done)

ADDED=$(parse_commits "^feat:")
FIXED=$(parse_commits "^fix:")
CHANGED=$(parse_commits "^(refactor|perf):")

# Exit if no semantic changes are found
[[ -z "$BREAKING$ADDED$FIXED$CHANGED" ]] && { echo "ℹ️ No semantic changes found."; exit 0; }

# --- MARKDOWN BUILDING ---
NEW_BLOCK="## [$VERSION] - $DATE"
[[ -n "$BREAKING" ]] && NEW_BLOCK="$NEW_BLOCK"$'\n\n'"### Removed (Breaking Changes)"$'\n'"$BREAKING"
[[ -n "$ADDED" ]]    && NEW_BLOCK="$NEW_BLOCK"$'\n\n'"### Added"$'\n'"$ADDED"
[[ -n "$FIXED" ]]    && NEW_BLOCK="$NEW_BLOCK"$'\n\n'"### Fixed"$'\n'"$FIXED"
[[ -n "$CHANGED" ]]  && NEW_BLOCK="$NEW_BLOCK"$'\n\n'"### Changed"$'\n'"$CHANGED"

# --- FILE INJECTION ---
TEMP_FILE=$(mktemp)

if [[ -f "$FILE" ]]; then
    if grep -qF -- "$PLACEHOLDER" "$FILE"; then
        # Inject after the first occurrence of the placeholder
        FOUND=false
        while IFS= read -r line || [[ -n "$line" ]]; do
            printf "%s\n" "$line" >> "$TEMP_FILE"
            if [[ "$line" == "$PLACEHOLDER" && "$FOUND" = false ]]; then
                printf "\n%s\n" "$NEW_BLOCK" >> "$TEMP_FILE"
                FOUND=true
            fi
        done < "$FILE"
        mv "$TEMP_FILE" "$FILE"
    else
        # Fallback: Inject after the first line (Title)
        { head -n 1 "$FILE"; printf "\n%s\n" "$NEW_BLOCK"; tail -n +2 "$FILE"; } > "$TEMP_FILE" && mv "$TEMP_FILE" "$FILE"
    fi
else
    # Create new file using dynamic parameters
    {
        printf "# %s\n\n" "$TITLE_TEXT"
        printf "%b\n\n" "$DESC_TEXT"
        printf "%s\n\n" "$PLACEHOLDER"
        printf "%s\n" "$NEW_BLOCK"
    } > "$FILE"
fi

rm -f "$TEMP_FILE"
printf "✅ Success: %s updated to version %s\n" "$FILE" "$VERSION"