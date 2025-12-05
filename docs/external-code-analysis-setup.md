# External Code Analysis Tools Setup Guide

This guide walks you through setting up external code analysis tools for the RDS Operations Dashboard project, in accordance with the AI SDLC Governance Framework.

## Overview

We integrate multiple external tools to provide comprehensive code analysis:

- **CodeRabbit**: AI-powered code review
- **Snyk**: Dependency vulnerability scanning
- **GitGuardian**: Secrets detection
- **Semgrep**: Security pattern analysis
- **SonarCloud**: Code quality and security
- **CodeClimate**: Maintainability analysis

## Prerequisites

- GitHub repository with admin access
- AWS account (for some integrations)
- OpenAI API key (for CodeRabbit)

## 1. CodeRabbit Setup

### Step 1: Install CodeRabbit GitHub App

1. Visit [CodeRabbit GitHub App](https://github.com/apps/coderabbitai)
2. Click "Install" and select your repository
3. Grant required permissions:
   - Read access to code
   - Write access to pull requests
   - Read access to metadata

### Step 2: Configure OpenAI API Key

1. Get an OpenAI API key from [OpenAI Platform](https://platform.openai.com/api-keys)
2. Add to GitHub repository secrets:
   ```
   Settings → Secrets and variables → Actions → New repository secret
   Name: OPENAI_API_KEY
   Value: sk-...
   ```

### Step 3: Verify Configuration

The `.coderabbit.yaml` file in the repository root configures CodeRabbit behavior. Key settings:

```yaml
reviews:
  profile: "assertive"  # More thorough reviews
  request_changes_workflow: true  # Block PRs with critical issues
  auto_review:
    enabled: true
```

### Step 4: Test CodeRabbit

1. Create a test branch
2. Make a code change
3. Open a pull request
4. CodeRabbit should automatically comment within 1-2 minutes

## 2. Snyk Setup

### Step 1: Create Snyk Account

1. Visit [Snyk.io](https://snyk.io)
2. Sign up with GitHub account
3. Import your repository

### Step 2: Get Snyk API Token

1. Go to Account Settings → API Token
2. Copy the token
3. Add to GitHub secrets:
   ```
   Name: SNYK_TOKEN
   Value: [your-token]
   ```

### Step 3: Configure Snyk

Create `snyk.json` in repository root:

```json
{
  "language-settings": {
    "python": {
      "targetFile": "requirements.txt"
    }
  },
  "severity-threshold": "high",
  "fail-on": "upgradable"
}
```

### Step 4: Test Snyk

```bash
# Install Snyk CLI
npm install -g snyk

# Authenticate
snyk auth

# Test for vulnerabilities
snyk test

# Monitor project
snyk monitor
```

## 3. GitGuardian Setup

### Step 1: Create GitGuardian Account

1. Visit [GitGuardian](https://www.gitguardian.com)
2. Sign up and connect GitHub
3. Install GitGuardian GitHub App

### Step 2: Get API Key

1. Go to API → Personal Access Tokens
2. Create new token with `scan` scope
3. Add to GitHub secrets:
   ```
   Name: GITGUARDIAN_API_KEY
   Value: [your-token]
   ```

### Step 3: Configure GitGuardian

Create `.gitguardian.yaml`:

```yaml
version: 2
paths-ignore:
  - "**/*.md"
  - "**/node_modules/**"
  - "**/.venv/**"

matches-ignore:
  - name: "Test credentials"
    match: "test_.*_key"
```

### Step 4: Test GitGuardian

```bash
# Install ggshield
pip install ggshield

# Scan repository
ggshield secret scan repo .
```

## 4. SonarCloud Setup

### Step 1: Create SonarCloud Account

1. Visit [SonarCloud.io](https://sonarcloud.io)
2. Sign in with GitHub
3. Import your organization and repository

### Step 2: Get SonarCloud Token

1. Go to My Account → Security
2. Generate new token
3. Add to GitHub secrets:
   ```
   Name: SONAR_TOKEN
   Value: [your-token]
   ```

### Step 3: Configure SonarCloud

Create `sonar-project.properties`:

```properties
sonar.projectKey=your-org_rds-operations-dashboard
sonar.organization=your-org

# Source directories
sonar.sources=rds-operations-dashboard/lambda,rds-operations-dashboard/frontend,rds-operations-dashboard/bff
sonar.tests=rds-operations-dashboard/lambda/tests

# Exclusions
sonar.exclusions=**/node_modules/**,**/*.test.ts,**/*.spec.ts

# Python specific
sonar.python.version=3.11

# TypeScript specific
sonar.typescript.lcov.reportPaths=coverage/lcov.info

# Quality gates
sonar.qualitygate.wait=true
```

### Step 4: Test SonarCloud

The GitHub Actions workflow will automatically run SonarCloud analysis on every PR.

## 5. Semgrep Setup

### Step 1: Create Semgrep Account (Optional)

1. Visit [Semgrep.dev](https://semgrep.dev)
2. Sign up for free tier
3. Connect GitHub repository

### Step 2: Configure Semgrep

Create `.semgrep.yml`:

```yaml
rules:
  - id: aws-lambda-missing-error-handling
    pattern: |
      def lambda_handler(event, context):
        ...
    message: Lambda handler should include try-except for error handling
    languages: [python]
    severity: WARNING

  - id: hardcoded-aws-credentials
    patterns:
      - pattern: aws_access_key_id = "..."
      - pattern: aws_secret_access_key = "..."
    message: Never hardcode AWS credentials
    languages: [python, javascript, typescript]
    severity: ERROR

  - id: sql-injection-risk
    pattern: |
      cursor.execute(f"... {$VAR} ...")
    message: Potential SQL injection - use parameterized queries
    languages: [python]
    severity: ERROR
```

### Step 3: Test Semgrep

```bash
# Install Semgrep
pip install semgrep

# Run scan
semgrep --config=auto .

# Run with specific rules
semgrep --config=p/security-audit .
```

## 6. CodeClimate Setup

### Step 1: Create CodeClimate Account

1. Visit [CodeClimate.com](https://codeclimate.com)
2. Sign up with GitHub
3. Add repository

### Step 2: Get Test Reporter ID

1. Go to Repo Settings → Test Coverage
2. Copy the Test Reporter ID
3. Add to GitHub secrets:
   ```
   Name: CC_TEST_REPORTER_ID
   Value: [your-id]
   ```

### Step 3: Configure CodeClimate

Create `.codeclimate.yml`:

```yaml
version: "2"

checks:
  argument-count:
    enabled: true
    config:
      threshold: 4
  complex-logic:
    enabled: true
    config:
      threshold: 4
  file-lines:
    enabled: true
    config:
      threshold: 250
  method-complexity:
    enabled: true
    config:
      threshold: 5
  method-count:
    enabled: true
    config:
      threshold: 20
  method-lines:
    enabled: true
    config:
      threshold: 25
  nested-control-flow:
    enabled: true
    config:
      threshold: 4
  return-statements:
    enabled: true
    config:
      threshold: 4
  similar-code:
    enabled: true
    config:
      threshold: 50
  identical-code:
    enabled: true
    config:
      threshold: 25

plugins:
  eslint:
    enabled: true
    channel: "eslint-8"
  
  pylint:
    enabled: true
  
  duplication:
    enabled: true
    config:
      languages:
        - python
        - javascript
        - typescript

exclude_patterns:
  - "config/"
  - "node_modules/"
  - "**/*.test.ts"
  - "**/*.spec.ts"
  - "**/tests/"
  - "**/__pycache__/"
  - "**/dist/"
  - "**/build/"
```

## 7. GitHub Actions Integration

The `.github/workflows/code-analysis.yml` workflow orchestrates all tools. It runs on:

- Every pull request
- Pushes to main/develop branches
- Manual trigger via workflow_dispatch

### Workflow Jobs

1. **coderabbit-review**: AI-powered code review
2. **security-scan**: Snyk, GitGuardian, Semgrep
3. **code-quality**: SonarCloud, CodeClimate
4. **python-analysis**: Pylint, Bandit, Ruff, Safety
5. **typescript-analysis**: ESLint, TypeScript compiler
6. **analysis-summary**: Aggregate results
7. **governance-logging**: Log to governance system

### Required Secrets

Add these to GitHub repository secrets:

```
OPENAI_API_KEY          # For CodeRabbit
SNYK_TOKEN              # For Snyk
GITGUARDIAN_API_KEY     # For GitGuardian
SONAR_TOKEN             # For SonarCloud
CC_TEST_REPORTER_ID     # For CodeClimate
```

## 8. Local Development Setup

### Install Tools Locally

```bash
# Python tools
pip install pylint bandit ruff safety

# Node.js tools
npm install -g eslint @typescript-eslint/parser @typescript-eslint/eslint-plugin

# Security tools
pip install ggshield
npm install -g snyk
pip install semgrep

# Run all checks locally
./scripts/run-local-analysis.sh
```

### Pre-commit Hooks

Install pre-commit hooks to run checks before committing:

```bash
# Install pre-commit
pip install pre-commit

# Install hooks
pre-commit install

# Run manually
pre-commit run --all-files
```

Create `.pre-commit-config.yaml`:

```yaml
repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.5.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-yaml
      - id: check-json
      - id: check-added-large-files
      - id: detect-private-key

  - repo: https://github.com/psf/black
    rev: 23.12.1
    hooks:
      - id: black

  - repo: https://github.com/charliermarsh/ruff-pre-commit
    rev: v0.1.9
    hooks:
      - id: ruff

  - repo: https://github.com/PyCQA/bandit
    rev: 1.7.6
    hooks:
      - id: bandit
        args: ['-c', 'pyproject.toml']

  - repo: https://github.com/gitguardian/ggshield
    rev: v1.23.0
    hooks:
      - id: ggshield
        language_version: python3
        stages: [commit]
```

## 9. Monitoring and Metrics

### Dashboard Setup

Create a dashboard to track analysis metrics:

1. **External Analysis Coverage (EAC)**: % of commits analyzed
2. **Critical Issue Resolution Time (CIRT)**: Time to fix critical issues
3. **False Positive Rate (FPR)**: % of false positives
4. **Tool Effectiveness**: Issues found per tool

### Metrics Collection

The governance logging job creates analysis logs in `.kiro/governance/`. Use these to track:

- Analysis frequency
- Issue trends over time
- Tool performance
- Developer response time

### Reporting

Generate weekly reports:

```bash
./scripts/generate-analysis-report.ps1 -Week 48 -Year 2025
```

## 10. Troubleshooting

### CodeRabbit Not Commenting

- Check GitHub App permissions
- Verify OPENAI_API_KEY is valid
- Check `.coderabbit.yaml` syntax
- Review CodeRabbit logs in PR checks

### Snyk Failing

- Verify SNYK_TOKEN is correct
- Check if dependencies are up to date
- Review Snyk dashboard for project status
- Ensure `package.json` or `requirements.txt` exists

### SonarCloud Not Running

- Verify SONAR_TOKEN is valid
- Check `sonar-project.properties` configuration
- Ensure project is imported in SonarCloud
- Review SonarCloud project settings

### GitGuardian False Positives

- Add patterns to `.gitguardian.yaml` ignore list
- Mark as false positive in GitGuardian dashboard
- Use `ggshield ignore` command

## 11. Best Practices

### Do's

✅ Review all tool findings, don't auto-dismiss
✅ Configure tools to match your standards
✅ Keep tool configurations in version control
✅ Run tools locally before pushing
✅ Address critical issues immediately
✅ Track metrics to measure effectiveness
✅ Update tool configurations as standards evolve

### Don'ts

❌ Don't ignore security warnings
❌ Don't disable tools without documentation
❌ Don't commit secrets (even test ones)
❌ Don't bypass checks without approval
❌ Don't forget to update dependencies
❌ Don't over-configure to cause alert fatigue

## 12. Support and Resources

### Documentation

- [CodeRabbit Docs](https://docs.coderabbit.ai)
- [Snyk Docs](https://docs.snyk.io)
- [GitGuardian Docs](https://docs.gitguardian.com)
- [SonarCloud Docs](https://docs.sonarcloud.io)
- [Semgrep Docs](https://semgrep.dev/docs)

### Community

- CodeRabbit Discord
- Snyk Community Forum
- SonarCloud Community

### Internal Support

- Governance Team: governance@company.com
- Security Team: security@company.com
- DevOps Team: devops@company.com

## Conclusion

With these tools configured, every code change will be automatically analyzed for:

- Security vulnerabilities
- Code quality issues
- Best practice violations
- Performance problems
- Maintainability concerns

This comprehensive analysis ensures high code quality and security compliance in accordance with the AI SDLC Governance Framework.
