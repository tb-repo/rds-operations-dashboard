# Git Setup Guide

## Understanding the Line Ending Warnings

The warnings you're seeing are normal:
```
warning: in the working copy of 'frontend/.env.example', LF will be replaced by CRLF the next time Git touches it
```

This happens because:
- **Windows uses CRLF** (Carriage Return + Line Feed) for line endings
- **Unix/Linux/Mac use LF** (Line Feed only) for line endings
- Git is converting between these formats automatically

**This is NOT an error** - it's just informational. Git will handle it correctly.

## Solution: .gitattributes File

I've created a `.gitattributes` file that tells Git how to handle line endings consistently:
- Shell scripts (`.sh`) will always use LF (Unix style)
- PowerShell scripts (`.ps1`) will always use CRLF (Windows style)
- Other text files will auto-detect

## Initial Git Setup - Step by Step

### Step 1: Configure Git (One-time setup)

```powershell
# Set your identity
git config --global user.name "Your Name"
git config --global user.email "your.email@example.com"

# Configure line ending handling (recommended for Windows)
git config --global core.autocrlf true

# Verify configuration
git config --list
```

### Step 2: Initialize Repository (if not done)

```powershell
# Navigate to project root
cd rds-operations-dashboard

# Check if git is initialized
git status

# If not initialized, run:
git init
```

### Step 3: Add Remote Repository

```powershell
# Add your GitHub repository
git remote add origin https://github.com/tb-repo/rds-operations-dashboard.git

# Verify remote
git remote -v
```

### Step 4: Stage All Files

```powershell
# Add all files (warnings are normal)
git add .

# Check what will be committed
git status
```

You'll see warnings about line endings - **this is expected and safe to ignore**.

### Step 5: Create Initial Commit

```powershell
# Create commit
git commit -m "Initial commit: RDS Operations Dashboard with deployment automation"

# Verify commit
git log --oneline
```

### Step 6: Push to GitHub

```powershell
# Set main as default branch
git branch -M main

# Push to GitHub
git push -u origin main
```

If the repository already has content:
```powershell
# Pull first, then push
git pull origin main --allow-unrelated-histories
git push -u origin main
```

## Common Git Commands

### Check Status
```powershell
git status
```

### View Changes
```powershell
# See what changed
git diff

# See staged changes
git diff --staged
```

### Commit Changes
```powershell
# Stage specific files
git add file1.txt file2.txt

# Stage all changes
git add .

# Commit with message
git commit -m "Your commit message"
```

### Push Changes
```powershell
# Push to main branch
git push origin main

# Push and set upstream
git push -u origin main
```

### Pull Latest Changes
```powershell
# Pull from main branch
git pull origin main
```

### View Commit History
```powershell
# View all commits
git log

# View compact history
git log --oneline

# View last 5 commits
git log --oneline -5
```

### Undo Changes

```powershell
# Discard changes in working directory
git checkout -- filename.txt

# Unstage a file
git reset HEAD filename.txt

# Undo last commit (keep changes)
git reset --soft HEAD~1

# Undo last commit (discard changes)
git reset --hard HEAD~1
```

## Handling Line Ending Warnings

### Option 1: Ignore Them (Recommended)
The warnings are informational only. Git will handle conversions correctly. Just proceed with your commits.

### Option 2: Suppress Warnings
```powershell
# Configure Git to not warn about line endings
git config --global core.safecrlf false
```

### Option 3: Normalize All Files
```powershell
# Remove all files from Git's index
git rm --cached -r .

# Re-add all files (Git will normalize line endings)
git add .

# Commit the normalization
git commit -m "Normalize line endings"
```

## GitHub Authentication

### Option 1: HTTPS with Personal Access Token

1. **Generate Token:**
   - Go to GitHub → Settings → Developer settings → Personal access tokens
   - Generate new token (classic)
   - Select scopes: `repo` (full control)
   - Copy the token

2. **Use Token as Password:**
   ```powershell
   git push origin main
   # Username: your-github-username
   # Password: paste-your-token-here
   ```

### Option 2: SSH Key

1. **Generate SSH Key:**
   ```powershell
   ssh-keygen -t ed25519 -C "your.email@example.com"
   ```

2. **Add to GitHub:**
   - Copy public key: `cat ~/.ssh/id_ed25519.pub`
   - Go to GitHub → Settings → SSH and GPG keys
   - Add new SSH key

3. **Change Remote to SSH:**
   ```powershell
   git remote set-url origin git@github.com:tb-repo/rds-operations-dashboard.git
   ```

## Troubleshooting

### "Permission denied" Error
- Check your GitHub credentials
- Verify you have write access to the repository
- Use Personal Access Token instead of password

### "Repository not found" Error
- Verify the repository URL is correct
- Check you're logged into the correct GitHub account
- Ensure the repository exists

### "Failed to push" Error
```powershell
# Pull latest changes first
git pull origin main --rebase

# Then push
git push origin main
```

### Large Files Warning
If you get warnings about large files:
```powershell
# Check file sizes
git ls-files | xargs ls -lh

# Remove large files from Git
git rm --cached path/to/large/file

# Add to .gitignore
echo "path/to/large/file" >> .gitignore
```

## Best Practices

1. **Commit Often:** Make small, focused commits
2. **Write Good Messages:** Describe what and why, not how
3. **Pull Before Push:** Always pull latest changes before pushing
4. **Use Branches:** Create feature branches for new work
5. **Review Changes:** Use `git diff` before committing
6. **Don't Commit Secrets:** Never commit passwords, API keys, or credentials

## Git Workflow for This Project

```powershell
# 1. Make changes to files
# Edit code, documentation, etc.

# 2. Check what changed
git status
git diff

# 3. Stage changes
git add .

# 4. Commit changes
git commit -m "Add deployment automation scripts"

# 5. Pull latest (if working with others)
git pull origin main

# 6. Push to GitHub
git push origin main

# 7. GitHub Actions will automatically deploy!
```

## Next Steps After Git Setup

1. ✅ Git configured and code pushed to GitHub
2. ⏭️ Set up GitHub Actions secrets (see DEPLOYMENT-GUIDE.md Part 3)
3. ⏭️ Deploy infrastructure (see DEPLOYMENT-GUIDE.md Part 4)
4. ⏭️ Deploy frontend (see DEPLOYMENT-GUIDE.md Part 5)

## Quick Reference

```powershell
# Initial setup
git init
git remote add origin https://github.com/tb-repo/rds-operations-dashboard.git
git add .
git commit -m "Initial commit"
git branch -M main
git push -u origin main

# Daily workflow
git status                    # Check status
git add .                     # Stage all changes
git commit -m "message"       # Commit changes
git pull origin main          # Pull latest
git push origin main          # Push changes

# View history
git log --oneline            # View commits
git diff                     # View changes

# Undo changes
git checkout -- file.txt     # Discard changes
git reset HEAD file.txt      # Unstage file
```

## Need Help?

- **Git Documentation:** https://git-scm.com/doc
- **GitHub Guides:** https://guides.github.com/
- **Git Cheat Sheet:** https://education.github.com/git-cheat-sheet-education.pdf

---

**Ready to proceed?** After pushing to GitHub, continue with [DEPLOYMENT-GUIDE.md](DEPLOYMENT-GUIDE.md) Part 3 to set up GitHub Actions.
