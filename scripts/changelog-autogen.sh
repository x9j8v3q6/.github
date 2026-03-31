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
STRICT_MODE=false 

TITLE_TEXT="Changelog"
DESC_TEXT="All notable changes to this project will be documented in this file.\n\nThe format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),\nand this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html)."

usage() {
    printf "Usage: %s -v <version> -c <commits_string> [-x] [-d <date>] [-f <file>] [-t <title>] [-m <description>]\n" "$0"
    printf "Options:\n  -x : Strict mode (Errors if version exists OR no semantic changes found)\n"
    exit 1
}

# --- ARGUMENT PARSING ---
while getopts "v:c:d:f:t:m:xh" opt; do
    case ${opt} in
        v ) VERSION_INPUT=$OPTARG ;;
        c ) RAW_COMMITS=$OPTARG ;;
        d ) DATE=$OPTARG ;;
        f ) FILE=$OPTARG ;;
        t ) TITLE_TEXT=$OPTARG ;;
        m ) DESC_TEXT=$OPTARG ;;
        x ) STRICT_MODE=true ;; 
        * ) usage ;;
    esac
done

VERSION=$(echo "$VERSION_INPUT" | sed 's/^v//')
[[ -z "$VERSION" || -z "$RAW_COMMITS" ]] && usage

# --- VALIDATION: DUPLICATE VERSION CHECK ---
if [[ -f "$FILE" ]] && grep -qF -- "## [$VERSION]" "$FILE"; then
    if [[ "$STRICT_MODE" = true ]]; then
        printf "❌ Error: Version [%s] already exists in %s (Strict Mode ON).\n" "$VERSION" "$FILE"
        exit 1
    else
        printf "ℹ️ Version [%s] already exists. Skipping update.\n" "$VERSION"
        exit 0
    fi
fi

# --- PARSING ENGINE ---
# Function to clean and format a commit message line
# Example: "feat(auth): login" -> "Login"
format_line() {
    local line=$1
    local regex=$2
    # Remove prefix like feat(scope): or feat!:
    local CLEAN=$(echo "$line" | sed -E "s/$regex[[:space:]]*//I")
    # Uppercase first letter
    local FIRST=$(echo "${CLEAN:0:1}" | tr '[:lower:]' '[:upper:]')
    printf -- "- %s%s\n" "$FIRST" "${CLEAN:1}"
}

# Core Parser: Extract commits by regex, avoiding internal scopes
# Ignores (dev), (internal), (test) unless it's a Breaking Change
parse_public_commits() {
    local regex=$1
    echo "$RAW_COMMITS" | grep -vEi "\((dev|internal|test)\):" | grep -Ei "$regex" | while read -r line; do
        [[ -z "$line" ]] && continue
        format_line "$line" "$regex"
    done
}

# --- SECTION EXTRACTION ---

# 1. BREAKING CHANGES: Always visible (Criticality overrules visibility)
# Matches: feat!: msg or feat(scope)!: msg
BREAKING_REGEX="^[a-z]+(\(.*\))?\!:"
BREAKING=$(echo "$RAW_COMMITS" | grep -Ei "$BREAKING_REGEX" | while read -r line; do
    [[ -z "$line" ]] && continue
    format_line "$line" "$BREAKING_REGEX"
done)

# 2. SECTIONS (Using public filter)
ADDED=$(parse_public_commits "^feat(\(.*\))?:")
FIXED=$(parse_public_commits "^fix(\(.*\))?:")
CHANGED=$(parse_public_commits "^(refactor|perf)(\(.*\))?:")

# --- SEMANTIC CONTENT CHECK ---
if [[ -z "$BREAKING$ADDED$FIXED$CHANGED" ]]; then
    if [[ "$STRICT_MODE" = true ]]; then
        printf "❌ Error: No public semantic changes found and Strict Mode is ON.\n"
        exit 1
    else
        printf "ℹ️ No public semantic changes found. Skipping changelog update.\n"
        exit 0
    fi
fi

# --- MARKDOWN CONSTRUCTION ---
NEW_BLOCK="## [$VERSION] - $DATE"
[[ -n "$BREAKING" ]] && NEW_BLOCK="$NEW_BLOCK"$'\n\n'"### 🚨 Breaking Changes"$'\n'"$BREAKING"
[[ -n "$ADDED" ]]    && NEW_BLOCK="$NEW_BLOCK"$'\n\n'"### ✨ New Features"$'\n'"$ADDED"
[[ -n "$FIXED" ]]    && NEW_BLOCK="$NEW_BLOCK"$'\n\n'"### 🐛 Bug Fixes"$'\n'"$FIXED"
[[ -n "$CHANGED" ]]  && NEW_BLOCK="$NEW_BLOCK"$'\n\n'"### ⚡ Refactors & Optimizations"$'\n'"$CHANGED"

# --- FILE INJECTION ---
TEMP_FILE=$(mktemp)

if [[ -f "$FILE" ]]; then
    if grep -qF -- "$PLACEHOLDER" "$FILE"; then
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
        { head -n 1 "$FILE"; printf "\n%s\n" "$NEW_BLOCK"; tail -n +2 "$FILE"; } > "$TEMP_FILE" && mv "$TEMP_FILE" "$FILE"
    fi
else
    {
        printf "# %s\n\n" "$TITLE_TEXT"
        printf "%b\n\n" "$DESC_TEXT"
        printf "%s\n\n" "$PLACEHOLDER"
        printf "%s\n" "$NEW_BLOCK"
    } > "$FILE"
fi

rm -f "$TEMP_FILE"
printf "✅ Success: %s updated to version %s\n" "$FILE" "$VERSION"
