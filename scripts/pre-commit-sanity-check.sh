#!/usr/bin/env bash
# Pre-Commit Sanity Check
# Checks for secrets, PII, and risky files before committing
# Generated from .claude/workflows/pre-commit-sanity-check.md

set -uo pipefail

# ── Colors (Aardvark Blue palette) ──────────────────────────────────────────
GREEN=$'\033[38;2;75;140;15m'
BRIGHT_GREEN=$'\033[38;2;149;220;85m'
YELLOW=$'\033[38;2;219;186;0m'
BRIGHT_YELLOW=$'\033[38;2;255;231;99m'
RED=$'\033[38;2;170;52;46m'
BLUE=$'\033[38;2;19;112;211m'
BRIGHT_BLUE=$'\033[38;2;96;164;236m'
CYAN=$'\033[38;2;0;142;176m'
BRIGHT_CYAN=$'\033[38;2;96;182;203m'
MAGENTA=$'\033[38;2;196;58;194m'
DIM=$'\033[2m'
BOLD=$'\033[1m'
RESET=$'\033[0m'

# Symbols
CHECK_MARK="✓"
WARNING="⚠️"
CROSS="✗"
ARROW="→"

# Counters for findings
SECRETS_FOUND=0
PII_FOUND=0
RISKY_FILES_FOUND=0
GITIGNORE_ISSUES=0

# Arrays to store findings
declare -a SECRET_FINDINGS=()
declare -a PII_FINDINGS=()
declare -a RISKY_FILE_FINDINGS=()
declare -a GITIGNORE_SUGGESTIONS=()

# ── Helper functions ────────────────────────────────────────────────────────
print_header() {
    local text="$1"
    local text_len=${#text}
    local total_width=78
    local prefix="━━━ "
    local prefix_len=4
    local trailing=$((total_width - prefix_len - text_len - 1))
    printf -v bar '%*s' "$trailing" ''
    bar="${bar// /━}"
    echo
    echo "${BOLD}${BLUE}${prefix}${text} ${bar}${RESET}"
    sleep 0.5
}

print_success() {
    echo "${BRIGHT_GREEN}${CHECK_MARK}${RESET} $*"
    sleep 0.3
}

print_warning() {
    echo "${YELLOW}${WARNING}${RESET}  $*"
    sleep 0.25
}

print_error() {
    echo "${RED}${CROSS}${RESET} $*" >&2
    sleep 0.25
}

print_info() {
    echo "${BRIGHT_BLUE}${ARROW}${RESET} $*"
    sleep 0.25
}

# Get list of staged files
get_staged_files() {
    print_header "Identifying Files to Check"

    # Get staged files
    mapfile -t STAGED_FILES < <(git diff --cached --name-only 2>/dev/null)

    if [ ${#STAGED_FILES[@]} -eq 0 ]; then
        print_warning "No files are staged for commit"
        echo
        echo "Run ${BOLD}git add <files>${RESET} to stage files first"
        exit 0
    fi

    print_info "Found ${#STAGED_FILES[@]} staged file(s)"
    for file in "${STAGED_FILES[@]}"; do
        if [ -f "$file" ]; then
            echo "  - $file"
        else
            echo "  - $file ${YELLOW}(deleted)${RESET}"
        fi
    done
}

# Check for secrets
check_secrets() {
    print_header "Checking for Secrets and Credentials"

    print_info "Scanning ${#STAGED_FILES[@]} file(s) for API keys, tokens, passwords..."

    local secret_patterns=(
        'api[_-]?key.*=.*['\''"][a-zA-Z0-9]{20,}['\''"]'
        'password.*=.*['\''"].+['\''"]'
        'secret.*=.*['\''"].+['\''"]'
        'token.*=.*['\''"][a-zA-Z0-9_-]{20,}['\''"]'
        'bearer\s+[a-zA-Z0-9_-]{20,}'
        'sk-[a-zA-Z0-9]{20,}'
        'aws_access_key_id.*=.*['\''"][A-Z0-9]{20}['\''"]'
        'aws_secret_access_key.*=.*['\''"][a-zA-Z0-9/+]{40}['\''"]'
        'private[_-]?key.*BEGIN'
        'oauth.*['\''"][a-zA-Z0-9_-]{20,}['\''"]'
    )

    for file in "${STAGED_FILES[@]}"; do
        # Skip deleted files
        [ ! -f "$file" ] && continue

        # Skip markdown files in .claude/workflows (documentation)
        if [[ "$file" == *.md ]] && [[ "$file" == *".claude/workflows"* ]]; then
            continue
        fi

        # Check each pattern
        for pattern in "${secret_patterns[@]}"; do
            while IFS= read -r line; do
                local line_num="${line%%:*}"
                local content="${line#*:}"

                # Skip if it's just a variable name without value
                if echo "$content" | grep -qE '(getenv|process\.env|os\.environ|ENV\[|config\.|\.get\(|placeholder|example|your.*here|xxx|redacted)'; then
                    continue
                fi

                # Skip comments that are just explaining what should go there
                if echo "$content" | grep -qE '^\s*(#|//|/\*|\*).*'; then
                    # If it's a comment describing what key to use, skip it
                    if echo "$content" | grep -qiE '(your|insert|add|replace|set)'; then
                        continue
                    fi
                fi

                # Skip if it looks like a regex pattern definition (in backticks or code blocks)
                if echo "$content" | grep -qE '(```|`.*`|regex|pattern)'; then
                    continue
                fi

                SECRET_FINDINGS+=("$file:$line_num: $content")
                ((SECRETS_FOUND++))
            done < <(grep -nE "$pattern" "$file" 2>/dev/null || true)
        done
    done

    # Check for common secret files
    local secret_files=(
        '.env'
        '.env.local'
        '.env.production'
        'secrets.json'
        'credentials.json'
        '*.pem'
        '*.key'
        'id_rsa'
        'id_dsa'
        'id_ecdsa'
        'id_ed25519'
    )

    for file in "${STAGED_FILES[@]}"; do
        for secret_file_pattern in "${secret_files[@]}"; do
            if [[ "$file" == *"$secret_file_pattern"* ]] || [[ "$(basename "$file")" == $secret_file_pattern ]]; then
                SECRET_FINDINGS+=("$file: SECRET FILE - Should not be committed")
                ((SECRETS_FOUND++))
            fi
        done
    done

    if [ $SECRETS_FOUND -eq 0 ]; then
        print_success "No secrets found"
    else
        print_error "Found $SECRETS_FOUND potential secret(s)"
    fi
}

# Check for PII
check_pii() {
    print_header "Checking for Personally Identifiable Information (PII)"

    print_info "Scanning for email addresses, usernames in paths, real names..."

    for file in "${STAGED_FILES[@]}"; do
        # Skip deleted files
        [ ! -f "$file" ] && continue

        # Check for real email addresses (not placeholders)
        while IFS= read -r line; do
            local line_num="${line%%:*}"
            local content="${line#*:}"

            # Skip placeholder emails and safe service domains
            if echo "$content" | grep -qE '@(example\.com|domain\.com|test\.com|localhost|your-domain\.com|company\.com|anthropic\.com|github\.com)'; then
                continue
            fi

            # Skip if it's in a comment describing what email to use
            if echo "$content" | grep -qE '^\s*(#|//|/\*|\*).*'; then
                if echo "$content" | grep -qiE '(your|insert|add|replace|set|user|name).*@'; then
                    continue
                fi
            fi

            PII_FINDINGS+=("$file:$line_num: Real email address detected: $content")
            ((PII_FOUND++))
        done < <(grep -nE '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' "$file" 2>/dev/null | \
                 grep -vE '@(example\.com|domain\.com|test\.com|localhost)' || true)

        # Check for usernames in paths
        while IFS= read -r line; do
            local line_num="${line%%:*}"
            local content="${line#*:}"

            # Skip generic placeholders
            if echo "$content" | grep -qE '/(Users|home)/(user|username|john|jane|yourname|someone|admin|test)(/|$|[^a-zA-Z0-9])'; then
                continue
            fi

            # Extract the username from the path
            local username=""
            if [[ "$content" =~ /Users/([a-zA-Z][a-zA-Z0-9_-]+)/ ]]; then
                username="${BASH_REMATCH[1]}"
            elif [[ "$content" =~ /home/([a-zA-Z][a-zA-Z0-9_-]+)/ ]]; then
                username="${BASH_REMATCH[1]}"
            fi

            if [ -n "$username" ]; then
                PII_FINDINGS+=("$file:$line_num: Username in path: $username")
                ((PII_FOUND++))
            fi
        done < <(grep -nE '/(Users|home)/[a-zA-Z][a-zA-Z0-9_-]+/' "$file" 2>/dev/null || true)
    done

    if [ $PII_FOUND -eq 0 ]; then
        print_success "No PII found"
    else
        print_error "Found $PII_FOUND potential PII issue(s)"
    fi
}

# Check for risky files
check_risky_files() {
    print_header "Checking for Files That Shouldn't Be Committed"

    print_info "Scanning for generated scripts, temp files, OS files..."

    local risky_patterns=(
        '*launcher'
        '*.tmp'
        '*.bak'
        '*.swp'
        '*.swo'
        '.DS_Store'
        'Thumbs.db'
        '*.log'
        'node_modules/*'
        '.idea/*'
        '.vscode/*'
        '__pycache__/*'
        '*.pyc'
        '.pytest_cache/*'
        '.coverage'
        'coverage/*'
        'dist/*'
        'build/*'
        '*.egg-info/*'
    )

    for file in "${STAGED_FILES[@]}"; do
        local basename_file="$(basename "$file")"

        for pattern in "${risky_patterns[@]}"; do
            # Convert glob pattern to regex-like matching
            if [[ "$file" == $pattern ]] || [[ "$basename_file" == $pattern ]]; then
                RISKY_FILE_FINDINGS+=("$file: Risky file type or location")
                ((RISKY_FILES_FOUND++))
                break
            fi
        done

        # Check if it's an executable script with user-specific paths
        if [ -f "$file" ] && [ -x "$file" ]; then
            if grep -qE '/(Users|home)/[a-zA-Z][a-zA-Z0-9_-]+/' "$file" 2>/dev/null; then
                # Skip if it's a generic placeholder
                if ! grep -qE '/(Users|home)/(user|username|yourname)' "$file" 2>/dev/null; then
                    RISKY_FILE_FINDINGS+=("$file: Executable with user-specific paths")
                    ((RISKY_FILES_FOUND++))
                fi
            fi
        fi
    done

    if [ $RISKY_FILES_FOUND -eq 0 ]; then
        print_success "No risky files found"
    else
        print_warning "Found $RISKY_FILES_FOUND risky file(s)"
    fi
}

# Check .gitignore adequacy
check_gitignore() {
    print_header "Verifying .gitignore Coverage"

    if [ ! -f .gitignore ]; then
        print_error "No .gitignore file found"
        GITIGNORE_SUGGESTIONS+=("Create a .gitignore file")
        ((GITIGNORE_ISSUES++))
        return
    fi

    print_info "Checking .gitignore for common patterns..."

    local required_patterns=(
        '*.tmp:.tmp files'
        '*.bak:backup files'
        '.DS_Store:macOS files'
        'Thumbs.db:Windows files'
        '*.log:log files'
        '.env:.env files'
        '.env.local:local env files'
        'secrets.json:secret files'
        'credentials.json:credential files'
        '*.pem:private keys'
        '*.key:key files'
        'node_modules:node modules'
    )

    for pattern_info in "${required_patterns[@]}"; do
        local pattern="${pattern_info%%:*}"
        local description="${pattern_info#*:}"

        if ! grep -qE "^${pattern}$" .gitignore 2>/dev/null; then
            # Check if there's a more general pattern that would cover this
            local pattern_prefix="${pattern%%\**}"
            if [ -n "$pattern_prefix" ] && grep -qE "^${pattern_prefix}" .gitignore 2>/dev/null; then
                continue
            fi

            GITIGNORE_SUGGESTIONS+=("Add '$pattern' to ignore $description")
            ((GITIGNORE_ISSUES++))
        fi
    done

    if [ $GITIGNORE_ISSUES -eq 0 ]; then
        print_success ".gitignore looks adequate"
    else
        print_warning ".gitignore could be improved ($GITIGNORE_ISSUES suggestion(s))"
    fi
}

# Generate final report
generate_report() {
    print_header "Security Check Report"

    echo ""
    echo "${BOLD}Files to be committed:${RESET} ${#STAGED_FILES[@]}"
    echo ""

    # SECRETS
    echo "${BOLD}SECRETS:${RESET}"
    if [ $SECRETS_FOUND -eq 0 ]; then
        print_success "No secrets found"
    else
        print_error "Found $SECRETS_FOUND potential secret(s):"
        for finding in "${SECRET_FINDINGS[@]}"; do
            echo "  ${RED}${CROSS}${RESET} $finding"
        done
    fi
    echo ""

    # PII
    echo "${BOLD}PII:${RESET}"
    if [ $PII_FOUND -eq 0 ]; then
        print_success "No PII found"
    else
        print_error "Found $PII_FOUND potential PII issue(s):"
        for finding in "${PII_FINDINGS[@]}"; do
            echo "  ${RED}${CROSS}${RESET} $finding"
        done
    fi
    echo ""

    # RISKY FILES
    echo "${BOLD}RISKY FILES:${RESET}"
    if [ $RISKY_FILES_FOUND -eq 0 ]; then
        print_success "No risky files found"
    else
        print_warning "Found $RISKY_FILES_FOUND risky file(s):"
        for finding in "${RISKY_FILE_FINDINGS[@]}"; do
            echo "  ${YELLOW}${WARNING}${RESET} $finding"
        done
    fi
    echo ""

    # GITIGNORE
    echo "${BOLD}GITIGNORE:${RESET}"
    if [ $GITIGNORE_ISSUES -eq 0 ]; then
        print_success ".gitignore is adequate"
    else
        print_warning ".gitignore could be improved:"
        for suggestion in "${GITIGNORE_SUGGESTIONS[@]}"; do
            echo "  ${YELLOW}${ARROW}${RESET} $suggestion"
        done
    fi
    echo ""
}

# Generate verdict and exit
generate_verdict() {
    print_header "VERDICT"
    echo ""

    # Critical issues: secrets or PII
    local critical_issues=$((SECRETS_FOUND + PII_FOUND))

    # Warning issues: risky files or gitignore
    local warning_issues=$((RISKY_FILES_FOUND + GITIGNORE_ISSUES))

    if [ $critical_issues -gt 0 ]; then
        echo "${RED}${BOLD}❌ DO NOT COMMIT${RESET}"
        echo "${RED}Critical security issues must be fixed first${RESET}"
        echo ""
        echo "${BOLD}Recommended actions:${RESET}"
        if [ $SECRETS_FOUND -gt 0 ]; then
            echo "  1. Remove secrets from staged files"
            echo "  2. Store secrets in environment variables or .env file"
            echo "  3. Add .env to .gitignore"
        fi
        if [ $PII_FOUND -gt 0 ]; then
            echo "  1. Replace real email addresses with placeholders (user@example.com)"
            echo "  2. Replace user-specific paths with generic placeholders (/path/to/)"
            echo "  3. Review if PII is necessary in the code"
        fi
        echo ""
        exit 1
    elif [ $warning_issues -gt 0 ]; then
        echo "${YELLOW}${BOLD}⚠️  REVIEW NEEDED${RESET}"
        echo "${YELLOW}Minor issues found - review before committing${RESET}"
        echo ""
        if [ $RISKY_FILES_FOUND -gt 0 ]; then
            echo "Risky files detected. Consider:"
            echo "  - Adding them to .gitignore if they're generated"
            echo "  - Verifying they should be tracked in git"
        fi
        if [ $GITIGNORE_ISSUES -gt 0 ]; then
            echo ".gitignore improvements suggested above"
        fi
        echo ""
        # Only prompt if running interactively
        if [ -t 0 ]; then
            echo "Press ENTER to continue with commit, or Ctrl+C to abort"
            read -r
        fi
        exit 0
    else
        echo "${GREEN}${BOLD}✅ ALL CLEAR FOR COMMIT${RESET}"
        echo "${GREEN}No security issues detected${RESET}"
        echo ""
        exit 0
    fi
}

# Main execution
main() {
    echo "${BOLD}${BLUE}"
    cat << 'MASTHEAD'
╔═════════════════════════════════════════════════════════════════════════════╗
║   Pre-Commit Security Sanity Check                                          ║
╚═════════════════════════════════════════════════════════════════════════════╝
MASTHEAD
    echo "${RESET}"

    get_staged_files
    check_secrets
    check_pii
    check_risky_files
    check_gitignore
    generate_report
    generate_verdict
}

# Run main function
main
