#!/bin/bash
set -eu
shopt -s globstar

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

log_section() {
    echo -e "\n${PURPLE}=== $1 ===${NC}"
}

# Git setup function
_git_setup() {
    log_section "Setting up Git configuration"
    
    cat <<- EOF > $HOME/.netrc
      machine github.com
      login $GITHUB_ACTOR
      password $INPUT_GITHUB_TOKEN
      machine api.github.com
      login $GITHUB_ACTOR  
      password $INPUT_GITHUB_TOKEN
EOF
    chmod 600 $HOME/.netrc

    case "$INPUT_GIT_IDENTITY" in
        "author")
            git config --global user.name "$GITHUB_ACTOR"
            git config --global user.email "$GITHUB_ACTOR@users.noreply.github.com"
            log_info "Using GitHub actor identity: $GITHUB_ACTOR"
            ;;
        "actions")
            git config --global user.email "actions@github.com"
            git config --global user.name "GitHub Action"
            log_info "Using GitHub Actions identity"
            ;;
        "custom")
            if [ -n "$INPUT_GIT_USER_NAME" ] && [ -n "$INPUT_GIT_USER_EMAIL" ]; then
                git config --global user.name "$INPUT_GIT_USER_NAME"
                git config --global user.email "$INPUT_GIT_USER_EMAIL"
                log_info "Using custom identity: $INPUT_GIT_USER_NAME <$INPUT_GIT_USER_EMAIL>"
            else
                log_error "Custom git identity requires both git_user_name and git_user_email"
                exit 1
            fi
            ;;
        *)
            log_error "GIT_IDENTITY must be 'author', 'actions', or 'custom'"
            exit 1
            ;;
    esac
}

# Check if files changed
_git_changed() {
    [[ -n "$(git status -s)" ]]
}

# Install tools function
_install_tools() {
    log_section "Installing code formatting and linting tools"
    
    # Create package.json if it doesn't exist
    if [ ! -f "package.json" ]; then
        log_info "Creating temporary package.json"
        echo '{"name": "temp-formatter", "private": true}' > package.json
        TEMP_PACKAGE_JSON=true
    fi
    
    # Install Prettier
    if [ "$INPUT_ENABLE_PRETTIER" = "true" ]; then
        log_info "Installing Prettier $INPUT_PRETTIER_VERSION..."
        npm install --silent prettier@$INPUT_PRETTIER_VERSION
        
        # Install Prettier plugins
        if [ -n "$INPUT_PRETTIER_PLUGINS" ]; then
            log_info "Installing Prettier plugins: $INPUT_PRETTIER_PLUGINS"
            npm install --silent $INPUT_PRETTIER_PLUGINS
        fi
        
        # Auto-install common Prettier plugins if enabled
        if [ "$INPUT_AUTO_INSTALL_CONFIGS" = "true" ]; then
            COMMON_PRETTIER_PLUGINS=""
            
            # Check for Tailwind CSS
            if find . -name "tailwind.config.*" -o -name "*.config.js" | grep -q tailwind; then
                COMMON_PRETTIER_PLUGINS="$COMMON_PRETTIER_PLUGINS prettier-plugin-tailwindcss"
            fi
            
            # Check for TypeScript
            if find . -name "*.ts" -o -name "*.tsx" -o -name "tsconfig.json" | head -1 | grep -q .; then
                COMMON_PRETTIER_PLUGINS="$COMMON_PRETTIER_PLUGINS @typescript-eslint/prettier"
            fi
            
            if [ -n "$COMMON_PRETTIER_PLUGINS" ]; then
                log_info "Auto-installing common Prettier plugins: $COMMON_PRETTIER_PLUGINS"
                npm install --silent $COMMON_PRETTIER_PLUGINS || log_warning "Failed to install some Prettier plugins"
            fi
        fi
    fi
    
    # Install ESLint
    if [ "$INPUT_ENABLE_ESLINT" = "true" ]; then
        log_info "Installing ESLint $INPUT_ESLINT_VERSION..."
        npm install --silent eslint@$INPUT_ESLINT_VERSION
        
        # Install ESLint plugins
        if [ -n "$INPUT_ESLINT_PLUGINS" ]; then
            log_info "Installing ESLint plugins: $INPUT_ESLINT_PLUGINS"
            npm install --silent $INPUT_ESLINT_PLUGINS
        fi
        
        # Auto-install common ESLint configs if enabled  
        if [ "$INPUT_AUTO_INSTALL_CONFIGS" = "true" ]; then
            COMMON_ESLINT_CONFIGS=""
            
            # Check for TypeScript
            if find . -name "*.ts" -o -name "*.tsx" -o -name "tsconfig.json" | head -1 | grep -q .; then
                COMMON_ESLINT_CONFIGS="$COMMON_ESLINT_CONFIGS @typescript-eslint/eslint-plugin @typescript-eslint/parser"
            fi
            
            # Check for React
            if find . -name "*.jsx" -o -name "*.tsx" | head -1 | grep -q . || grep -q react package.json 2>/dev/null; then
                COMMON_ESLINT_CONFIGS="$COMMON_ESLINT_CONFIGS eslint-plugin-react eslint-plugin-react-hooks"
            fi
            
            # Check for Vue
            if find . -name "*.vue" | head -1 | grep -q . || grep -q vue package.json 2>/dev/null; then
                COMMON_ESLINT_CONFIGS="$COMMON_ESLINT_CONFIGS eslint-plugin-vue"
            fi
            
            # Always add Prettier integration
            COMMON_ESLINT_CONFIGS="$COMMON_ESLINT_CONFIGS eslint-config-prettier eslint-plugin-prettier"
            
            if [ -n "$COMMON_ESLINT_CONFIGS" ]; then
                log_info "Auto-installing common ESLint configs: $COMMON_ESLINT_CONFIGS"
                npm install --silent $COMMON_ESLINT_CONFIGS || log_warning "Failed to install some ESLint configs"
            fi
        fi
        
        # Create basic .eslintrc.js if it doesn't exist
        if [ ! -f ".eslintrc.js" ] && [ ! -f ".eslintrc.json" ] && [ ! -f ".eslintrc.yml" ] && [ ! -f "eslint.config.js" ]; then
            log_info "Creating basic ESLint configuration"
            cat > .eslintrc.js << 'EOF'
module.exports = {
  env: {
    browser: true,
    es2021: true,
    node: true,
  },
  extends: [
    'eslint:recommended',
    ...(require('fs').existsSync('./tsconfig.json') ? ['@typescript-eslint/recommended'] : []),
    ...(require('fs').existsSync('./package.json') && JSON.parse(require('fs').readFileSync('./package.json')).dependencies?.react ? ['plugin:react/recommended', 'plugin:react-hooks/recommended'] : []),
    'prettier'
  ],
  parser: require('fs').existsSync('./tsconfig.json') ? '@typescript-eslint/parser' : undefined,
  parserOptions: {
    ecmaVersion: 'latest',
    sourceType: 'module',
    ...(require('fs').existsSync('./package.json') && JSON.parse(require('fs').readFileSync('./package.json')).dependencies?.react ? { ecmaFeatures: { jsx: true } } : {}),
  },
  plugins: [
    ...(require('fs').existsSync('./tsconfig.json') ? ['@typescript-eslint'] : []),
    ...(require('fs').existsSync('./package.json') && JSON.parse(require('fs').readFileSync('./package.json')).dependencies?.react ? ['react', 'react-hooks'] : []),
    'prettier'
  ],
  rules: {
    'prettier/prettier': 'error'
  },
  settings: {
    ...(require('fs').existsSync('./package.json') && JSON.parse(require('fs').readFileSync('./package.json')).dependencies?.react ? { react: { version: 'detect' } } : {})
  }
};
EOF
            TEMP_ESLINT_CONFIG=true
        fi
    fi
    
    # Install Stylelint
    if [ "$INPUT_ENABLE_STYLELINT" = "true" ]; then
        log_info "Installing Stylelint $INPUT_STYLELINT_VERSION..."
        npm install --silent stylelint@$INPUT_STYLELINT_VERSION
        
        # Install Stylelint plugins
        if [ -n "$INPUT_STYLELINT_PLUGINS" ]; then
            log_info "Installing Stylelint plugins: $INPUT_STYLELINT_PLUGINS"
            npm install --silent $INPUT_STYLELINT_PLUGINS
        fi
        
        # Auto-install common Stylelint configs
        if [ "$INPUT_AUTO_INSTALL_CONFIGS" = "true" ]; then
            COMMON_STYLELINT_CONFIGS="stylelint-config-standard stylelint-prettier"
            log_info "Auto-installing common Stylelint configs: $COMMON_STYLELINT_CONFIGS"
            npm install --silent $COMMON_STYLELINT_CONFIGS || log_warning "Failed to install some Stylelint configs"
        fi
        
        # Create basic stylelint config if it doesn't exist
        if [ ! -f ".stylelintrc.js" ] && [ ! -f ".stylelintrc.json" ] && [ ! -f "stylelint.config.js" ]; then
            log_info "Creating basic Stylelint configuration"
            cat > .stylelintrc.json << 'EOF'
{
  "extends": ["stylelint-config-standard"],
  "plugins": ["stylelint-prettier"],
  "rules": {
    "prettier/prettier": true
  }
}
EOF
            TEMP_STYLELINT_CONFIG=true
        fi
    fi
}

# Run formatting and linting
_run_tools() {
    log_section "Running code formatting and linting"
    
    local has_errors=false
    local changes_made=false
    
    # Run Prettier
    if [ "$INPUT_ENABLE_PRETTIER" = "true" ]; then
        log_info "Running Prettier..."
        if [ "$INPUT_CHECK_ONLY" = "true" ]; then
            prettier --check $INPUT_PRETTIER_OPTIONS 2>&1 | tee -a $GITHUB_STEP_SUMMARY || {
                log_warning "Prettier found formatting issues"
                has_errors=true
            }
        else
            prettier $INPUT_PRETTIER_OPTIONS 2>&1 | tee -a $GITHUB_STEP_SUMMARY && {
                log_success "Prettier formatting completed"
                changes_made=true
            } || {
                log_error "Prettier failed"
                has_errors=true
            }
        fi
    fi
    
    # Run ESLint
    if [ "$INPUT_ENABLE_ESLINT" = "true" ]; then
        log_info "Running ESLint..."
        if [ "$INPUT_CHECK_ONLY" = "true" ]; then
            eslint $INPUT_ESLINT_OPTIONS 2>&1 | tee -a $GITHUB_STEP_SUMMARY || {
                log_warning "ESLint found issues"
                has_errors=true
            }
        else
            eslint $INPUT_ESLINT_OPTIONS 2>&1 | tee -a $GITHUB_STEP_SUMMARY && {
                log_success "ESLint linting completed"
                changes_made=true
            } || {
                log_warning "ESLint found some issues (may have been partially fixed)"
                changes_made=true
                if [ "$INPUT_FAIL_ON_ERROR" = "true" ]; then
                    has_errors=true
                fi
            }
        fi
    fi
    
    # Run Stylelint
    if [ "$INPUT_ENABLE_STYLELINT" = "true" ]; then
        log_info "Running Stylelint..."
        if [ "$INPUT_CHECK_ONLY" = "true" ]; then
            stylelint $INPUT_STYLELINT_OPTIONS 2>&1 | tee -a $GITHUB_STEP_SUMMARY || {
                log_warning "Stylelint found issues"
                has_errors=true
            }
        else
            stylelint $INPUT_STYLELINT_OPTIONS 2>&1 | tee -a $GITHUB_STEP_SUMMARY && {
                log_success "Stylelint linting completed"
                changes_made=true
            } || {
                log_warning "Stylelint found some issues (may have been partially fixed)"
                changes_made=true
                if [ "$INPUT_FAIL_ON_ERROR" = "true" ]; then
                    has_errors=true
                fi
            }
        fi
    fi
    
    if [ "$has_errors" = "true" ] && [ "$INPUT_FAIL_ON_ERROR" = "true" ]; then
        log_error "Linting errors found and fail_on_error is enabled"
        exit 1
    fi
}

# Handle only changed files
_handle_only_changed() {
    if [ "$INPUT_ONLY_CHANGED" = "true" ] || [ "$INPUT_ONLY_CHANGED_PR" = "true" ]; then
        BASE_BRANCH="HEAD~1"
        if [ "$INPUT_ONLY_CHANGED_PR" = "true" ]; then
            BASE_BRANCH="origin/$GITHUB_BASE_REF"
        fi
        
        log_info "Processing only files changed since $BASE_BRANCH"
        
        # Get list of changed files
        git diff --name-only HEAD $BASE_BRANCH > /tmp/prev.txt
        git diff --name-only HEAD > /tmp/cur.txt
        
        # Reset files that weren't changed in the target commit
        OLDIFS="$IFS"
        IFS=$'\n'
        for file in $(comm -1 -3 /tmp/prev.txt /tmp/cur.txt); do
            log_info "Resetting unchanged file: $file"
            git restore -- "$file" 2>/dev/null || true
        done
        IFS="$OLDIFS"
    fi
}

# Cleanup temporary files
_cleanup() {
    log_section "Cleaning up"
    
    # Remove node_modules if requested
    if [ "$INPUT_CLEAN_NODE_FOLDER" = "true" ] && [ -d 'node_modules' ]; then
        log_info "Removing node_modules folder..."
        rm -rf node_modules/
    fi
    
    # Remove temporary package.json
    if [ "${TEMP_PACKAGE_JSON:-false}" = "true" ]; then
        log_info "Removing temporary package.json"
        rm -f package.json
    fi
    
    # Remove temporary configs
    if [ "${TEMP_ESLINT_CONFIG:-false}" = "true" ]; then
        log_info "Removing temporary ESLint config"
        rm -f .eslintrc.js
    fi
    
    if [ "${TEMP_STYLELINT_CONFIG:-false}" = "true" ]; then
        log_info "Removing temporary Stylelint config"
        rm -f .stylelintrc.json
    fi
    
    # Reset package-lock.json if it exists
    if [ -f 'package-lock.json' ]; then
        git checkout -- package-lock.json 2>/dev/null || log_info "No package-lock.json tracked by git"
    fi
}

# Main execution
main() {
    log_section "Enhanced Code Formatter & Linter Action"
    log_info "Working directory: ${INPUT_WORKING_DIRECTORY:-.}"
    
    # Change to working directory
    if [ -n "$INPUT_WORKING_DIRECTORY" ] && [ "$INPUT_WORKING_DIRECTORY" != "." ]; then
        cd "$INPUT_WORKING_DIRECTORY"
    fi
    
    # Install tools
    _install_tools
    
    # Run tools
    _run_tools
    
    # Handle only changed files
    _handle_only_changed
    
    # Check if we have changes to commit
    if _git_changed; then
        if [ "$INPUT_DRY" = "true" ]; then
            log_warning "DRY RUN: Changes detected but not committing"
            echo "## Changes Preview" >> $GITHUB_STEP_SUMMARY
            git diff >> $GITHUB_STEP_SUMMARY
            
            if [ "$INPUT_NO_COMMIT" = "false" ]; then
                exit 1
            fi
        elif [ "$INPUT_NO_COMMIT" = "true" ]; then
            log_info "Changes made but not committing (no_commit=true)"
        else
            # Setup git and commit changes
            _git_setup
            
            log_section "Committing changes"
            git add "${INPUT_FILE_PATTERN}" || log_warning "Problem adding files with pattern ${INPUT_FILE_PATTERN}"
            
            if [ "$INPUT_SAME_COMMIT" = "true" ]; then
                log_info "Amending current commit..."
                git pull
                git commit --amend --no-edit --allow-empty
                git push origin -f ${INPUT_PUSH_OPTIONS:-}
            else
                # Prepare commit command
                COMMIT_CMD="git commit -m \"$INPUT_COMMIT_MESSAGE\""
                
                if [ -n "$INPUT_COMMIT_DESCRIPTION" ]; then
                    COMMIT_CMD="$COMMIT_CMD -m \"$INPUT_COMMIT_DESCRIPTION\""
                fi
                
                COMMIT_CMD="$COMMIT_CMD --author=\"$GITHUB_ACTOR <$GITHUB_ACTOR@users.noreply.github.com>\""
                
                if [ -n "$INPUT_COMMIT_OPTIONS" ]; then
                    COMMIT_CMD="$COMMIT_CMD $INPUT_COMMIT_OPTIONS"
                fi
                
                # Execute commit
                eval $COMMIT_CMD || log_warning "No files added to commit"
                git push origin ${INPUT_PUSH_OPTIONS:-}
            fi
            
            log_success "Changes committed and pushed successfully!"
            
            # Add summary to GitHub Actions
            echo "## ✅ Code Formatting Completed" >> $GITHUB_STEP_SUMMARY
            echo "- Prettier: $INPUT_ENABLE_PRETTIER" >> $GITHUB_STEP_SUMMARY
            echo "- ESLint: $INPUT_ENABLE_ESLINT" >> $GITHUB_STEP_SUMMARY  
            echo "- Stylelint: $INPUT_ENABLE_STYLELINT" >> $GITHUB_STEP_SUMMARY
            echo "- Commit: $INPUT_COMMIT_MESSAGE" >> $GITHUB_STEP_SUMMARY
        fi
    else
        log_success "No changes needed - code is already properly formatted!"
        echo "## ✅ No Changes Needed" >> $GITHUB_STEP_SUMMARY
        echo "All code is already properly formatted and linted." >> $GITHUB_STEP_SUMMARY
    fi
    
    # Cleanup
    _cleanup
    
    log_success "Action completed successfully!"
}

# Execute main function
main