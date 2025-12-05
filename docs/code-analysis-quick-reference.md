# Code Analysis Quick Reference

Quick reference for developers working with external code analysis tools.

## 🚀 Quick Start

### Before Committing

```bash
# Run all local checks
./scripts/run-local-analysis.ps1

# Auto-fix issues where possible
./scripts/run-local-analysis.ps1 -Fix

# Skip specific checks
./scripts/run-local-analysis.ps1 -SkipSecurity
```

### Install Tools Locally

```bash
# Python tools
pip install pylint bandit ruff safety ggshield semgrep

# Node.js tools
npm install -g eslint snyk

# Pre-commit hooks
pip install pre-commit
pre-commit install
```

## 🔍 Tool Overview

| Tool | Purpose | Severity | Auto-Fix |
|------|---------|----------|----------|
| **CodeRabbit** | AI code review | All | No |
| **Snyk** | Dependency vulnerabilities | High/Critical | Partial |
| **GitGuardian** | Secrets detection | Critical | No |
| **Semgrep** | Security patterns | Medium/High | No |
| **Pylint** | Python code quality | Low/Medium | No |
| **Bandit** | Python security | High/Critical | No |
| **Ruff** | Python linting | Low | Yes |
| **ESLint** | TypeScript/JavaScript | Low/Medium | Yes |
| **SonarCloud** | Overall quality | All | No |

## 📋 Common Issues & Fixes

### Python

**Issue: Pylint score too low**
```bash
# Check specific file
pylint lambda/discovery/handler.py

# Auto-format with black
black lambda/

# Fix with ruff
ruff check lambda/ --fix
```

**Issue: Bandit security warning**
```python
# Bad: Hardcoded password
password = "admin123"

# Good: Use environment variable
password = os.environ.get("DB_PASSWORD")
```

**Issue: Vulnerable dependency**
```bash
# Check vulnerabilities
safety check -r requirements.txt

# Update specific package
pip install --upgrade boto3

# Update all packages
pip install --upgrade -r requirements.txt
```

### TypeScript

**Issue: ESLint errors**
```bash
# Check specific file
npx eslint src/App.tsx

# Auto-fix
npx eslint src/ --fix

# Check all files
npm run lint
```

**Issue: TypeScript type errors**
```bash
# Check types
npx tsc --noEmit

# Common fixes:
# 1. Add type annotations
const user: User = { name: "John" }

# 2. Use type assertion
const element = document.getElementById("root") as HTMLElement

# 3. Add null check
if (user?.email) { ... }
```

### Security

**Issue: Exposed secret**
```bash
# Scan for secrets
ggshield secret scan repo .

# If false positive, add to .gitguardian.yaml:
matches-ignore:
  - name: "Test API key"
    match: "test_api_key_.*"
```

**Issue: SQL injection risk**
```python
# Bad: String interpolation
query = f"SELECT * FROM users WHERE id = {user_id}"

# Good: Parameterized query
query = "SELECT * FROM users WHERE id = %s"
cursor.execute(query, (user_id,))
```

**Issue: XSS vulnerability**
```typescript
// Bad: Direct HTML insertion
element.innerHTML = userInput

// Good: Use textContent or sanitize
element.textContent = userInput
// Or use DOMPurify
element.innerHTML = DOMPurify.sanitize(userInput)
```

## 🎯 Severity Guidelines

### Critical (Must Fix Before Merge)
- Exposed credentials or API keys
- SQL injection vulnerabilities
- Authentication bypass
- Remote code execution risks
- High-severity dependency vulnerabilities

### High (Should Fix Before Merge)
- Missing input validation
- Improper error handling
- Insecure cryptography
- Missing authentication checks
- Medium-severity dependency vulnerabilities

### Medium (Fix Soon)
- Code duplication
- Missing tests
- Performance issues
- Deprecated API usage
- Code complexity

### Low (Nice to Have)
- Code style issues
- Minor optimizations
- Documentation improvements
- Typos in comments

## 🔧 Configuration Files

### `.coderabbit.yaml`
Controls CodeRabbit behavior:
- Review thoroughness
- Auto-review settings
- Path-specific instructions
- Ignore patterns

### `.semgrep.yml`
Custom security rules:
- Pattern matching
- Language-specific rules
- Severity levels

### `.gitguardian.yaml`
Secrets detection config:
- Ignore patterns
- False positive handling

### `sonar-project.properties`
SonarCloud configuration:
- Source directories
- Quality gates
- Exclusions

## 📊 Metrics & Reports

### View Analysis Results

**GitHub PR Comments**
- CodeRabbit comments appear automatically
- Other tools post check results
- Click "Details" to see full reports

**Tool Dashboards**
- CodeRabbit: https://coderabbit.ai
- Snyk: https://app.snyk.io
- SonarCloud: https://sonarcloud.io
- GitGuardian: https://dashboard.gitguardian.com

**Local Reports**
```bash
# Generate local report
./scripts/generate-analysis-report.ps1

# View in browser
start analysis-report.html
```

## 🚫 What NOT to Do

❌ Don't commit with critical issues
❌ Don't disable security checks without approval
❌ Don't ignore CodeRabbit suggestions without review
❌ Don't hardcode secrets (even for testing)
❌ Don't bypass pre-commit hooks
❌ Don't merge PRs with failing checks
❌ Don't mark all warnings as false positives

## ✅ Best Practices

✅ Run local analysis before pushing
✅ Address CodeRabbit feedback constructively
✅ Fix critical/high issues immediately
✅ Keep dependencies up to date
✅ Write tests for new code
✅ Document complex logic
✅ Use environment variables for config
✅ Follow language-specific best practices

## 🆘 Getting Help

### Tool Not Working?

1. Check GitHub Actions logs
2. Verify secrets are configured
3. Review tool-specific documentation
4. Check `.github/workflows/code-analysis.yml`

### False Positive?

1. Verify it's actually a false positive
2. Add to tool-specific ignore config
3. Document why it's ignored
4. Get approval from security team for security issues

### Need Exception?

1. Document the reason
2. Get approval (see governance framework)
3. Log in `.kiro/governance/exceptions.md`
4. Schedule remediation

## 📚 Resources

- [Full Setup Guide](./external-code-analysis-setup.md)
- [AI SDLC Governance Framework](../../.kiro/steering/ai-sdlc-governance.md)
- [CodeRabbit Docs](https://docs.coderabbit.ai)
- [Snyk Docs](https://docs.snyk.io)
- [SonarCloud Docs](https://docs.sonarcloud.io)

## 🔄 Workflow

```
1. Write code
   ↓
2. Run local analysis (./scripts/run-local-analysis.ps1)
   ↓
3. Fix critical/high issues
   ↓
4. Commit changes
   ↓
5. Push to GitHub
   ↓
6. Automated analysis runs
   ↓
7. Review CodeRabbit comments
   ↓
8. Address feedback
   ↓
9. Get approval
   ↓
10. Merge PR
```

## 💡 Pro Tips

- Use `--fix` flags to auto-fix simple issues
- Run analysis frequently, not just before commits
- Keep tool configurations in sync with team standards
- Review analysis trends to identify patterns
- Contribute custom rules for project-specific issues
- Share learnings with the team
- Update this guide as you discover new tips!

---

**Remember**: These tools are here to help you write better, more secure code. Embrace the feedback and use it to improve! 🚀
