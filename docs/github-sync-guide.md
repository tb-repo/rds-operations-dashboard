# GitHub Sync Guide

This guide explains how to sync your RDS Operations Dashboard code to GitHub.

## Quick Sync

Use the automated sync script:

```powershell
# From the rds-operations-dashboard directory
./scripts/sync-to-github.ps1 -Message "Your commit message here"
```

## Manual Sync Steps

If you prefer to sync manually:

### 1. Check Status

```powershell
cd rds-operations-dashboard
git status
```

### 2. Stage Changes

```powershell
# Stage all changes
git add -A

# Or stage specific files
git add path/to/file
```

### 3. Commit Changes

```powershell
git commit -m "Your descriptive commit message"
```

### 4. Push to GitHub

```powershell
# Push to main branch
git push origin main

# Or push to a different branch
git push origin your-branch-name
```

## Current Repository

Your repository is connected to:
- **URL**: https://github.com/tb-repo/rds-operations-dashboard.git
- **Branch**: main

## Common Scenarios

### Scenario 1: First Time Push

If this is your first push to a new repository:

```powershell
# Add remote (if not already added)
git remote add origin https://github.com/tb-repo/rds-operations-dashboard.git

# Push and set upstream
git push -u origin main
```

### Scenario 2: Sync After Making Changes

```powershell
# Quick sync with script
./scripts/sync-to-github.ps1 -Message "Add external code analysis integration"
```

### Scenario 3: Pull Latest Changes

Before pushing, you might want to pull latest changes:

```powershell
# Pull latest from main
git pull origin main

# Then push your changes
git push origin main
```

### Scenario 4: Resolve Conflicts

If you encounter conflicts:

```powershell
# Pull with rebase
git pull --rebase origin main

# Resolve conflicts in your editor
# Then continue
git rebase --continue

# Push changes
git push origin main
```

### Scenario 5: Create Feature Branch

For new features, create a branch:

```powershell
# Create and switch to new branch
git checkout -b feature/your-feature-name

# Make changes and commit
git add -A
git commit -m "Add new feature"

# Push to new branch
git push origin feature/your-feature-name
```

## What's Currently Staged

Based on your current status, you have:

### Staged Changes (Ready to Commit)
- ✅ Archive organization (moved old session files)
- ✅ BFF implementation (Backend for Frontend)
- ✅ Auth & RBAC implementation
- ✅ Frontend authentication pages
- ✅ Infrastructure updates (CDK stacks)
- ✅ Lambda functions updates
- ✅ Governance and monitoring improvements
- ✅ Documentation updates

### Unstaged Changes (Need to Stage)
- Modified: README.md
- Modified: frontend components and pages
- Modified: infrastructure/bin/app.ts
- Modified: scripts/fix-lambda-shared-module.ps1

### Untracked Files (New Files)
- docs/BUSINESS-PRESENTATION.md
- docs/EXTERNAL-ANALYSIS-INTEGRATION-SUMMARY.md
- docs/code-analysis-quick-reference.md
- docs/external-code-analysis-setup.md
- frontend/src/components/SkeletonLoader.tsx
- frontend/src/components/Toast.tsx
- frontend/src/contexts/
- frontend/src/hooks/
- infrastructure/lib/frontend-stack.ts
- scripts/run-local-analysis.ps1

## Recommended Sync Strategy

### Option 1: Sync Everything Now

```powershell
# Stage all changes (staged + unstaged + untracked)
git add -A

# Commit with descriptive message
git commit -m "feat: Add external code analysis, frontend stack, and business presentation

- Integrate CodeRabbit and SonarCloud for code analysis
- Add frontend deployment infrastructure (S3 + CloudFront)
- Create business presentation documentation
- Add skeleton loader and toast components
- Implement custom hooks and contexts
- Update governance and monitoring"

# Push to GitHub
git push origin main
```

### Option 2: Sync in Phases

**Phase 1: Commit staged changes**
```powershell
git commit -m "feat: Major infrastructure and auth improvements

- Archive old session documentation
- Implement BFF with authentication
- Add Auth & RBAC with Cognito
- Update all infrastructure stacks
- Enhance governance and monitoring"

git push origin main
```

**Phase 2: Commit unstaged and new files**
```powershell
git add -A
git commit -m "feat: Add external code analysis and frontend enhancements

- Integrate CodeRabbit and SonarCloud
- Add frontend deployment stack
- Create business presentation
- Add UI components (skeleton loader, toast)
- Implement custom hooks and contexts"

git push origin main
```

## Using the Sync Script

The automated script handles everything:

```powershell
# Basic usage
./scripts/sync-to-github.ps1

# With custom message
./scripts/sync-to-github.ps1 -Message "Add code analysis integration"

# To different branch
./scripts/sync-to-github.ps1 -Message "Feature update" -Branch feature/analysis

# Force push (use with caution!)
./scripts/sync-to-github.ps1 -Message "Force update" -Force
```

## Best Practices

1. **Commit Often**: Make small, focused commits
2. **Descriptive Messages**: Use clear commit messages
3. **Pull Before Push**: Always pull latest changes before pushing
4. **Branch Strategy**: Use feature branches for new work
5. **Review Changes**: Use `git diff` to review before committing
6. **Test First**: Ensure code works before pushing

## Commit Message Conventions

Follow conventional commits format:

```
<type>(<scope>): <subject>

<body>

<footer>
```

**Types:**
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style changes (formatting)
- `refactor`: Code refactoring
- `test`: Adding tests
- `chore`: Maintenance tasks

**Examples:**
```
feat(auth): Add Cognito PKCE authentication
fix(bff): Resolve CORS issues in BFF middleware
docs(readme): Update deployment instructions
refactor(lambda): Improve error handling in discovery function
```

## Troubleshooting

### Authentication Issues

If you get authentication errors:

```powershell
# Configure Git credentials
git config --global user.name "Your Name"
git config --global user.email "your.email@example.com"

# Use GitHub CLI for authentication
gh auth login

# Or use personal access token
# Generate token at: https://github.com/settings/tokens
```

### Push Rejected

If push is rejected:

```powershell
# Pull with rebase
git pull --rebase origin main

# Resolve conflicts if any
# Then push
git push origin main
```

### Large Files

If you have large files:

```powershell
# Check file sizes
git ls-files | xargs ls -lh | sort -k5 -h -r | head -20

# Use Git LFS for large files
git lfs install
git lfs track "*.zip"
git lfs track "*.tar.gz"
```

## Integration with CodeRabbit

Once you push to GitHub, CodeRabbit will automatically:
1. Analyze your code on every PR
2. Provide inline comments and suggestions
3. Check for security vulnerabilities
4. Verify code quality standards

See `.coderabbit.yaml` for configuration.

## Next Steps

After syncing to GitHub:

1. **Enable Branch Protection**: Protect main branch in GitHub settings
2. **Set Up CI/CD**: GitHub Actions workflows are already configured
3. **Configure CodeRabbit**: Install CodeRabbit app on your repository
4. **Review Workflows**: Check `.github/workflows/` for automation
5. **Create PR Template**: Add `.github/pull_request_template.md`

## Support

For issues:
- Check GitHub documentation: https://docs.github.com
- Review Git documentation: https://git-scm.com/doc
- See CodeRabbit docs: https://docs.coderabbit.ai
