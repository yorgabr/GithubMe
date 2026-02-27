#!/usr/bin/env bash

# init_github_repo.sh
#
# This script automates the complete setup of a Git repository from local initialization
# to GitHub publication on Linux/Unix systems.
#
# Author: Yorga Babuscan (yorgabr@gmail.com)

set -euo pipefail

SCRIPT_VERSION="1.2.0"

#__________ Script metadata and state _____________________________________________________________
GITHUB_USER=""
GITHUB_REPO=""
DEFAULT_GIT_NAME=""
DEFAULT_GIT_EMAIL=""
DEV_NAME=""
DEV_EMAIL=""
PACK_VERSION="0.1.0"
VERBOSE=0
SET_LOCAL_GIT_CONFIG=1
REMOTE_CREATED=0
REMOTE_URL=""
GITHUB_TOKEN=""

#__________ Color helpers for rich console output _________________________________________________
ESC=$'\033'
Cyan="${ESC}[36m"
Yellow="${ESC}[33m"
Green="${ESC}[32m"
Red="${ESC}[31m"
Reset="${ESC}[0m"

#__________ Output functions ______________________________________________________________________
out_info() {
    if [[ $VERBOSE -eq 1 ]]; then
        printf "%b[INFO]%b %s\n" "$Cyan" "$Reset" "$1"
    fi
}

out_warn() {
    printf "%b[WARN]%b %s\n" "$Yellow" "$Reset" "$1"
}

out_success() {
    if [[ $VERBOSE -eq 1 ]]; then
        printf "%b[SUCCESS]%b %s\n" "$Green" "$Reset" "$1"
    fi
}

out_error() {
    printf "%b[ERROR]%b %s\n" "$Red" "$Reset" "$1" >&2
}

#__________ Git configuration helpers _____________________________________________________________
get_git_config() {
    local key="$1"
    local value
    value=$(git config "$key" 2>/dev/null || echo "")
    echo "$value"
}

#__________ Utility functions _____________________________________________________________________
get_script_name() {
    basename -- "$0"
}

show_version() {
    printf "%s version %s\n" "$(get_script_name)" "$SCRIPT_VERSION"
}

show_usage() {
    cat << 'USAGE'
init_github_repo.sh — Initialize a Git repository with proper tagging and release structure.

Usage:
    init_github_repo.sh --github-user <username> --github-repo <name> [options]

Required Arguments:
    --github-user USERNAME      GitHub username or organization for remote URL.
    --github-repo NAME          Repository name.

Options:
    --version                   Show script semantic version and exit.
    --help, -h                  Show this help and exit.
    --dev-name NAME             Developer's full name (default: --github-user value,
                                or git config user.name if set).
    --dev-email EMAIL           Developer's e-mail (default: git config user.email
                                if set, otherwise empty).
    --pack-version SEMVER       Package version for tag (default: 0.1.0).
    --create-remote             Create the repository on GitHub via API.
    --private                   Make the GitHub repository private (default: public).
    --token TOKEN               GitHub personal access token (required for --create-remote).
    --api-base-url URL          GitHub Enterprise API URL (default: https://api.github.com).
    --set-local-git-config      Set user.name and user.email in local git config
                                for this repository only (default: true).
    --no-set-local-git-config   Disable setting local git config (use global).
    --verbose                   Echo each step.
    --generate-completion SCOPE
                                Generate and install bash completion.
                                SCOPE can be: TEMP, USER, or SYSTEM.

Examples:
    # Basic local initialization
    init_github_repo.sh --github-user john --github-repo myproject

    # Create public repository on GitHub
    init_github_repo.sh --github-user john --github-repo myproject --create-remote --token "$token"

    # Create private repository with full specification
    init_github_repo.sh --github-user acme-corp --github-repo internal-tool \
        --dev-name "Jane Doe" --dev-email "jane@acme.com" \
        --pack-version 1.0.0 --create-remote --private --token "$token"

    # Generate and install autocomplete for current user
    init_github_repo.sh --generate-completion USER

Author: Yorga Babuscan (yorgabr@gmail.com)
USAGE
}

#__________ Bash completion infrastructure ________________________________________________________
get_completion_script() {
    cat << 'COMPLETION'
# init_github_repo.sh bash completion
# Generated automatically - do not edit manually

_Init-GitHubRepo.sh() {
    local cur prev opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    
    local long_opts="--github-user --github-repo --dev-name --dev-email 
                     --pack-version --create-remote --private --token 
                     --api-base-url --set-local-git-config 
                     --no-set-local-git-config --verbose 
                     --version --help --generate-completion"
    
    case "$prev" in
        --github-user|--github-repo|--dev-name|--dev-email|--pack-version|--token|--api-base-url|--generate-completion)
            return 0
            ;;
    esac
    
    if [[ "$cur" == -* ]]; then
        COMPREPLY=( $(compgen -W "${long_opts}" -- "$cur") )
        return 0
    fi
    
    return 0
}

complete -F _Init-GitHubRepo.sh init_github_repo.sh
COMPLETION
}

install_completion_temp() {
    out_info "Installing bash completion for current session (TEMP)..."
    eval "$(get_completion_script)"
    out_success "Bash completion activated for current session."
}

install_completion_user() {
    out_info "Installing bash completion for user (USER)..."
    
    local completion_dir="${HOME}/.local/share/bash-completion/completions"
    local completion_file="${completion_dir}/init_github_repo.sh"
    
    if [[ ! -d "$completion_dir" ]]; then
        out_info "Creating directory: $completion_dir"
        mkdir -p "$completion_dir" || {
            out_error "Failed to create directory: $completion_dir"
            exit 1
        }
    fi
    
    get_completion_script > "$completion_file" || {
        out_error "Failed to write completion file: $completion_file"
        exit 1
    }
    
    out_success "Bash completion installed to: $completion_file"
    out_info "To activate immediately, run: source '$completion_file'"
    out_info "Or restart your terminal."
}

install_completion_system() {
    out_info "Installing bash completion system-wide (SYSTEM)..."
    
    if [[ $EUID -ne 0 ]]; then
        out_error "System-wide installation requires root privileges."
        out_info "Please run with sudo: sudo $0 --generate-completion SYSTEM"
        exit 1
    fi
    
    local completion_dir="/etc/bash_completion.d"
    local completion_file="${completion_dir}/init_github_repo.sh"
    
    if [[ ! -d "$completion_dir" ]]; then
        out_error "Directory does not exist: $completion_dir"
        out_info "Your system may not have bash-completion installed."
        exit 1
    fi
    
    get_completion_script > "$completion_file" || {
        out_error "Failed to write completion file: $completion_file"
        exit 1
    }
    
    chmod 644 "$completion_file" || out_warn "Could not set permissions on $completion_file"
    
    out_success "Bash completion installed to: $completion_file"
    out_info "All users will have completion available after starting a new shell."
}

handle_generate_completion() {
    local scope="$1"
    
    case "$scope" in
        TEMP)
            install_completion_temp
            ;;
        USER)
            install_completion_user
            ;;
        SYSTEM)
            install_completion_system
            ;;
        *)
            out_error "Invalid scope for --generate-completion: $scope"
            out_info "Valid scopes are: TEMP, USER, SYSTEM"
            exit 1
            ;;
    esac
}

#__________ Argument processing ___________________________________________________________________
initialize_arguments() {
    # Handle completion generation first
    if [[ -n "${GENERATE_COMPLETION:-}" ]]; then
        handle_generate_completion "$GENERATE_COMPLETION"
        exit 0
    fi

    # Handle version display
    if [[ "${SHOW_VERSION:-0}" -eq 1 ]]; then
        show_version
        exit 0
    fi

    # Handle help display
    if [[ "${SHOW_HELP:-0}" -eq 1 ]]; then
        show_usage
        exit 0
    fi

    # Validate conflicting git config flags
    if [[ "${SET_LOCAL_GIT_CONFIG_FLAG:-0}" -eq 1 && "${NO_SET_LOCAL_GIT_CONFIG_FLAG:-0}" -eq 1 ]]; then
        out_error "Cannot use both --set-local-git-config and --no-set-local-git-config"
        exit 2
    fi
    
    if [[ "${NO_SET_LOCAL_GIT_CONFIG_FLAG:-0}" -eq 1 ]]; then
        SET_LOCAL_GIT_CONFIG=0
    fi

    # Validate required parameters
    if [[ -z "$GITHUB_USER" ]]; then
        out_error "Missing required argument: --github-user"
        show_usage
        exit 2
    fi

    if [[ -z "$GITHUB_REPO" ]]; then
        out_error "Missing required argument: --github-repo"
        show_usage
        exit 2
    fi

    # Validate GitHub creation requirements
    if [[ "${CREATE_REMOTE:-0}" -eq 1 && -z "$GITHUB_TOKEN" ]]; then
        out_error "--create-remote requires --token parameter for GitHub authentication"
        exit 2
    fi

    # Determine developer name with cascading fallback
    if [[ -z "$DEV_NAME" ]]; then
        if [[ -n "$DEFAULT_GIT_NAME" ]]; then
            DEV_NAME="$DEFAULT_GIT_NAME"
            out_info "Using git config user.name for dev-name: $DEV_NAME"
        else
            DEV_NAME="$GITHUB_USER"
            out_info "Using github-user for dev-name: $DEV_NAME"
        fi
    fi

    # Determine developer email with optional fallback
    if [[ -z "$DEV_EMAIL" ]]; then
        if [[ -n "$DEFAULT_GIT_EMAIL" ]]; then
            DEV_EMAIL="$DEFAULT_GIT_EMAIL"
            out_info "Using git config user.email for dev-email: $DEV_EMAIL"
        else
            DEV_EMAIL=""
            out_info "No dev-email provided and no git config user.email set. Leaving empty."
        fi
    fi
}

#__________ GitHub API integration ________________________________________________________________
new_github_repository() {
    local owner="$1"
    local name="$2"
    local token="$3"
    local is_private="${4:-false}"
    local api_url="${5:-https://api.github.com}"
    
    local visibility="public"
    if [[ "$is_private" == "true" ]]; then
        visibility="private"
    fi
    
    out_info "Creating ${visibility} repository '$name' on GitHub..."
    
    local uri="$api_url/user/repos"
    
    # Check if creating for organization
    local user_login
    user_login=$(curl -s -H "Authorization: Bearer $token" "$api_url/user" | grep -o '"login":"[^"]*"' | cut -d'"' -f4)
    
    if [[ "$owner" != "$user_login" ]]; then
        uri="$api_url/orgs/$owner/repos"
    fi
    
    local json_body
    json_body=$(cat <<EOF
{
    "name": "$name",
    "private": $is_private,
    "auto_init": false,
    "description": "Repository created by init_github_repo.sh"
}
EOF
)
    
    local response
    local http_code
    response=$(curl -s -w "\n%{http_code}" \
        -X POST \
        -H "Authorization: Bearer $token" \
        -H "Accept: application/vnd.github.v3+json" \
        -H "Content-Type: application/json" \
        -d "$json_body" \
        "$uri")
    
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')
    
    if [[ "$http_code" -eq 201 ]]; then
        REMOTE_CREATED=1
        REMOTE_URL=$(echo "$body" | grep -o '"clone_url":"[^"]*"' | cut -d'"' -f4)
        local html_url
        html_url=$(echo "$body" | grep -o '"html_url":"[^"]*"' | cut -d'"' -f4)
        out_success "Repository created successfully at $html_url"
        echo "$body"
    else
        if [[ "$http_code" -eq 422 ]]; then
            out_error "Repository '$name' already exists under '$owner' or name is invalid."
        elif [[ "$http_code" -eq 401 ]]; then
            out_error "Authentication failed. Please verify your GitHub token has 'repo' scope."
        elif [[ "$http_code" -eq 403 ]]; then
            out_error "Permission denied. Ensure your token has repository creation rights."
        else
            out_error "GitHub API error (${http_code}): $body"
        fi
        return 1
    fi
}

#__________ Git operations ________________________________________________________________________
initialize_git_repository() {
    if [[ ! -d ".git" ]]; then
        out_info "Initializing git repository..."
        
        if ! git init; then
            out_error "Failed to initialize git repository."
            exit 1
        fi
        
        if ! git checkout -b main 2>/dev/null; then
            if ! git checkout -b master 2>/dev/null; then
                out_error "Failed to create main/master branch."
                exit 1
            fi
        fi
        
        out_success "Git repository initialized."
    else
        out_info "Git repository already exists."
    fi

    # Apply local Git configuration if requested
    if [[ $SET_LOCAL_GIT_CONFIG -eq 1 ]]; then
        out_info "Setting local git config for this repository..."
        
        if [[ -n "$DEV_NAME" ]]; then
            if git config --local user.name "$DEV_NAME"; then
                out_success "Set local user.name: $DEV_NAME"
            else
                out_warn "Failed to set local user.name"
            fi
        fi
        
        if [[ -n "$DEV_EMAIL" ]]; then
            if git config --local user.email "$DEV_EMAIL"; then
                out_success "Set local user.email: $DEV_EMAIL"
            else
                out_warn "Failed to set local user.email"
            fi
        fi
        
        # Display current configuration for verification
        local local_name local_email
        local_name=$(git config --local user.name 2>/dev/null || echo "(not set)")
        local_email=$(git config --local user.email 2>/dev/null || echo "(not set)")
        out_info "Local git config for this repository:"
        out_info "  user.name:  $local_name"
        out_info "  user.email: $local_email"
    else
        out_info "Using global git config (local config not set)"
        if [[ -n "$DEV_NAME" ]]; then
            git config user.name "$DEV_NAME" 2>/dev/null || true
        fi
        if [[ -n "$DEV_EMAIL" ]]; then
            git config user.email "$DEV_EMAIL" 2>/dev/null || true
        fi
    fi
}

new_initial_commit() {
    out_info "Adding files to git..."
    
    if ! git add .; then
        out_error "Failed to add files to git."
        exit 1
    fi
    
    out_info "Creating initial commit..."
    
    local commit_message
    commit_message="Initial commit: $GITHUB_REPO

- Project setup with proper structure
- Version $PACK_VERSION"
    
    if [[ -n "$DEV_EMAIL" ]]; then
        commit_message="$commit_message
- Author: $DEV_NAME <$DEV_EMAIL>"
    else
        commit_message="$commit_message
- Author: $DEV_NAME"
    fi
    
    if git commit -m "$commit_message"; then
        out_success "Initial commit created."
    else
        out_warn "Nothing to commit or commit failed."
    fi
}

new_version_tag() {
    out_info "Creating tag v$PACK_VERSION..."
    
    local tag_message
    tag_message="Release v$PACK_VERSION

Initial release of $GITHUB_REPO."
    
    if [[ -n "$DEV_EMAIL" ]]; then
        tag_message="$tag_message
Author: $DEV_NAME <$DEV_EMAIL>"
    else
        tag_message="$tag_message
Author: $DEV_NAME"
    fi
    
    if git tag -a "v$PACK_VERSION" -m "$tag_message" 2>/dev/null; then
        out_success "Tag v$PACK_VERSION created."
    else
        out_warn "Tag v$PACK_VERSION may already exist."
    fi
}

new_release_notes() {
    out_info "Generating release notes..."
    
    local author_line
    if [[ -n "$DEV_EMAIL" ]]; then
        author_line="$DEV_NAME ($DEV_EMAIL)"
    else
        author_line="$DEV_NAME"
    fi
    
    cat > RELEASE_NOTES.md << EOF
# Release v$PACK_VERSION

## What's New
- First stable release of $GITHUB_REPO
- Project initialized and configured

## Installation

Download appropriate package for your platform from the releases section.

## Documentation
See README.md and CONTRIBUTING.md for details.

Author: $author_line
EOF
    
    out_success "Release notes created: RELEASE_NOTES.md"
}

add_git_remote() {
    local remote_url="$1"
    
    out_info "Adding remote origin..."
    
    if ! git remote add origin "$remote_url" 2>/dev/null; then
        # Remote might already exist, try to update URL
        if ! git remote set-url origin "$remote_url" 2>/dev/null; then
            out_warn "Could not configure remote origin. You may need to add it manually."
            return
        fi
    fi
    
    out_info "Pushing to GitHub..."
    
    # Determine default branch name
    local branch_name
    branch_name=$(git branch --show-current 2>/dev/null || echo "main")
    
    if git push -u origin "$branch_name" 2>/dev/null; then
        out_success "Pushed branch '$branch_name' to GitHub."
    else
        out_warn "Failed to push branch. You may need to push manually."
    fi
    
    if git push origin "v$PACK_VERSION" 2>/dev/null; then
        out_success "Pushed tag v$PACK_VERSION to GitHub."
    else
        out_warn "Failed to push tag. You may need to push it manually."
    fi
}

show_remote_instructions() {
    echo ""
    out_info "To connect to GitHub, run:"
    out_info "  git remote add origin https://github.com/$GITHUB_USER/$GITHUB_REPO.git"
    out_info "  git push -u origin main"
    echo ""
    out_info "To push tag to GitHub:"
    out_info "  git push origin v$PACK_VERSION"
    echo ""
    
    # Display current Git identity
    local current_name current_email
    current_name=$(git config user.name 2>/dev/null || echo "(not set)")
    current_email=$(git config user.email 2>/dev/null || echo "(not set)")
    out_info "Git identity for this repository:"
    out_info "  Commit will use: $current_name <$current_email>"
    
    if [[ $SET_LOCAL_GIT_CONFIG -eq 1 ]]; then
        local local_name local_email global_name global_email
        local_name=$(git config --local user.name 2>/dev/null || echo "(not set)")
        local_email=$(git config --local user.email 2>/dev/null || echo "(not set)")
        global_name=$(git config --global user.name 2>/dev/null || echo "(not set)")
        global_email=$(git config --global user.email 2>/dev/null || echo "(not set)")
        
        echo ""
        out_info "Local git config was set. Future commits in this repo will use:"
        out_info "  user.name:  $local_name"
        out_info "  user.email: $local_email"
        echo ""
        out_info "Your global git config remains unchanged:"
        out_info "  global user.name:  $global_name"
        out_info "  global user.email: $global_email"
    else
        echo ""
        out_info "Using global git config (not modified for this repo)"
    fi
}

#__________ Main execution flow ___________________________________________________________________
invoke_main() {
    initialize_arguments
    
    if [[ $VERBOSE -eq 1 ]]; then
        out_info "Running $(get_script_name) version $SCRIPT_VERSION"
    fi
    out_info "Initializing repository: $GITHUB_REPO"
    out_info "GitHub user: $GITHUB_USER"
    
    local dev_info="$DEV_NAME"
    if [[ -n "$DEV_EMAIL" ]]; then
        dev_info="$DEV_NAME <$DEV_EMAIL>"
    fi
    out_info "Developer: $dev_info"
    out_info "Package version: $PACK_VERSION"
    
    if [[ $SET_LOCAL_GIT_CONFIG -eq 1 ]]; then
        out_info "Will set local git config: YES"
    else
        out_info "Will set local git config: NO (using global)"
    fi
    
    if [[ "${CREATE_REMOTE:-0}" -eq 1 ]]; then
        local remote_type="public"
        if [[ "${PRIVATE_REPO:-0}" -eq 1 ]]; then
            remote_type="private"
        fi
        out_info "Will create GitHub repository: YES ($remote_type)"
    fi
    
    # Execute initialization phases
    initialize_git_repository
    new_initial_commit
    new_version_tag
    new_release_notes
    
    # GitHub remote creation and push
    if [[ "${CREATE_REMOTE:-0}" -eq 1 ]]; then
        local api_url="${API_BASE_URL:-https://api.github.com}"
        local is_private="false"
        if [[ "${PRIVATE_REPO:-0}" -eq 1 ]]; then
            is_private="true"
        fi
        
        if new_github_repository "$GITHUB_USER" "$GITHUB_REPO" "$GITHUB_TOKEN" "$is_private" "$api_url"; then
            add_git_remote "$REMOTE_URL"
        else
            out_warn "GitHub repository creation failed. You can create it manually and push."
            show_remote_instructions
            exit 1
        fi
    else
        show_remote_instructions
    fi
    
    # Finalization
    out_success "=== Initialization complete ==="
    if [[ "${CREATE_REMOTE:-0}" -eq 0 ]]; then
        out_info "Next steps:"
        out_info "1. Create repository on GitHub: https://github.com/new"
        out_info "2. Run: git remote add origin https://github.com/$GITHUB_USER/$GITHUB_REPO.git"
        out_info "3. Run: git push -u origin main"
        out_info "4. Run: git push origin v$PACK_VERSION"
        out_info "5. Upload release artifacts"
    else
        out_info "Your repository is now live on GitHub and ready for development."
    fi
}

#__________ Argument parsing ______________________________________________________________________
parse_args() {
    # Initialize flags
    SHOW_VERSION=0
    SHOW_HELP=0
    SET_LOCAL_GIT_CONFIG_FLAG=0
    NO_SET_LOCAL_GIT_CONFIG_FLAG=0
    CREATE_REMOTE=0
    PRIVATE_REPO=0
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --version)
                SHOW_VERSION=1
                shift
                ;;
            --help|-h)
                SHOW_HELP=1
                shift
                ;;
            --verbose)
                VERBOSE=1
                shift
                ;;
            --set-local-git-config)
                SET_LOCAL_GIT_CONFIG_FLAG=1
                SET_LOCAL_GIT_CONFIG=1
                shift
                ;;
            --no-set-local-git-config)
                NO_SET_LOCAL_GIT_CONFIG_FLAG=1
                SET_LOCAL_GIT_CONFIG=0
                shift
                ;;
            --create-remote)
                CREATE_REMOTE=1
                shift
                ;;
            --private)
                PRIVATE_REPO=1
                shift
                ;;
            --github-user)
                shift
                if [[ $# -gt 0 ]]; then
                    GITHUB_USER="$1"
                    shift
                else
                    out_error "--github-user requires a username."
                    exit 2
                fi
                ;;
            --github-repo)
                shift
                if [[ $# -gt 0 ]]; then
                    GITHUB_REPO="$1"
                    shift
                else
                    out_error "--github-repo requires a repository name."
                    exit 2
                fi
                ;;
            --dev-name)
                shift
                if [[ $# -gt 0 ]]; then
                    DEV_NAME="$1"
                    shift
                else
                    out_error "--dev-name requires a name."
                    exit 2
                fi
                ;;
            --dev-email)
                shift
                if [[ $# -gt 0 ]]; then
                    DEV_EMAIL="$1"
                    shift
                else
                    out_error "--dev-email requires an e-mail."
                    exit 2
                fi
                ;;
            --pack-version)
                shift
                if [[ $# -gt 0 ]]; then
                    PACK_VERSION="$1"
                    shift
                else
                    out_error "--pack-version requires a semantic version."
                    exit 2
                fi
                ;;
            --token)
                shift
                if [[ $# -gt 0 ]]; then
                    GITHUB_TOKEN="$1"
                    shift
                else
                    out_error "--token requires a GitHub personal access token."
                    exit 2
                fi
                ;;
            --api-base-url)
                shift
                if [[ $# -gt 0 ]]; then
                    API_BASE_URL="$1"
                    shift
                else
                    out_error "--api-base-url requires a URL."
                    exit 2
                fi
                ;;
            --generate-completion)
                shift
                if [[ $# -gt 0 ]]; then
                    GENERATE_COMPLETION="$1"
                    shift
                else
                    out_error "--generate-completion requires a scope argument (TEMP|USER|SYSTEM)."
                    exit 2
                fi
                ;;
            *)
                out_error "Unknown option: $1"
                show_usage
                exit 2
                ;;
        esac
    done
    
    # Initialize defaults from Git config
    DEFAULT_GIT_NAME=$(get_git_config "user.name")
    DEFAULT_GIT_EMAIL=$(get_git_config "user.email")
}

#__________ Entry point ___________________________________________________________________________
main() {
    parse_args "$@"
    invoke_main
}

main "$@"