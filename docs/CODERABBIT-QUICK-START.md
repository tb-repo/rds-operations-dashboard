# CodeRabbit Quick Start Guide

## 🚀 Get Started in 5 Minutes

### Step 1: Install CodeRabbit (2 minutes)

**Option A: Via CodeRabbit Website (Recommended)**
1. **Go to CodeRabbit**
   - Visit: https://coderabbit.ai
   - Click "Sign Up" or "Get Started"
   - Sign in with your GitHub account

2. **Connect Repository**
   - Select: `tb-repo/rds-operations-dashboard`
   - Authorize CodeRabbit to access your repo
   - Click "Install"

3. **Done!**
   - CodeRabbit is now active on your repo

**Option B: Via GitHub Marketplace**
1. **Go to GitHub Marketplace**
   - Visit: https://github.com/marketplace
   - Search for "CodeRabbit" or "AI code review"
   - Click on CodeRabbit listing

2. **Install the App**
   - Click "Set up a plan" (they have a free tier)
   - Select your repository
   - Authorize the app

**Option C: Direct Repository Settings**
1. **Go to Your Repository**
   - Visit: https://github.com/tb-repo/rds-operations-dashboard
   - Click "Settings" → "Integrations" → "GitHub Apps"
   - Search for and install CodeRabbit

**Note:** If CodeRabbit is not available or you prefer alternatives, see the "Alternative Tools" section below.

### Step 2: Test It (3 minutes)

Create a test PR to see CodeRabbit in action:

```bash
# Create a test branch
git checkout -b test/coderabbit-demo

# Create a file with intentional issues
cat > test-file.ts << 'EOF'
// This file has issues CodeRabbit will catch

const API_KEY = "sk-1234567890";  // Hardcoded secret

function getData(url) {  // Missing types
  fetch(url).then(r => r.json());  // No error handling
}

var x = 10;  // Use const/let

if (x == 10) {  // Use ===
  console.log("test");
}
EOF

# Commit and push
git add test-file.ts
git commit -m "test: Add file to test CodeRabbit"
git push origin test/coderabbit-demo
```

### Step 3: Create PR on GitHub

1. Go to your repository
2. Click "Pull requests" → "New pull request"
3. Select `test/coderabbit-demo` branch
4. Click "Create pull request"

### Step 4: Watch CodeRabbit Work

Within 30-60 seconds, you'll see:

```
🤖 CodeRabbit commented

## Summary
Found 5 issues in test-file.ts

### Critical Issues (1)
- 🔴 Hardcoded API key detected

### High Priority (2)
- 🟠 Missing error handling in async operation
- 🟠 Missing TypeScript types

### Medium Priority (2)
- 🟡 Use === instead of ==
- 🟡 Use const instead of var
```

## 📊 What Your Configuration Does

### Your Settings (`.coderabbit.yaml`)

#### 1. **Assertive Profile**
```yaml
profile: "assertive"
```
- More thorough reviews
- Catches more issues
- More detailed feedback

#### 2. **Blocks Critical Issues**
```yaml
request_changes_workflow: true
```
- PRs with critical issues can't be merged
- Forces fixes before merge

#### 3. **Auto-Review Enabled**
```yaml
auto_review:
  enabled: true
  drafts: false
```
- Reviews every PR automatically
- Skips draft PRs

#### 4. **Path-Specific Instructions**

**For Lambda Functions:**
```yaml
path: "rds-operations-dashboard/lambda/**/*.py"
```
Checks:
- AWS Lambda best practices
- Error handling and retry logic
- Security (IAM, secrets)
- Performance (cold starts)
- Logging

**For Infrastructure (CDK):**
```yaml
path: "rds-operations-dashboard/infrastructure/**/*.ts"
```
Checks:
- CDK best practices
- Security (least privilege, encryption)
- Cost optimization
- High availability
- Tagging

**For Frontend (React):**
```yaml
path: "rds-operations-dashboard/frontend/**/*.{ts,tsx}"
```
Checks:
- React best practices
- TypeScript type safety
- Accessibility (WCAG)
- Performance
- Security (XSS prevention)

**For BFF (Backend for Frontend):**
```yaml
path: "rds-operations-dashboard/bff/**/*.ts"
```
Checks:
- API security
- Input validation
- Error handling
- Rate limiting
- CORS configuration

#### 5. **Integrated Tools**

Your configuration enables:
- **ShellCheck**: Validates shell scripts
- **Ruff**: Python linter
- **MarkdownLint**: Documentation quality
- **LanguageTool**: Grammar and spelling

#### 6. **Knowledge Base**

CodeRabbit knows about your project:
```yaml
knowledge_base:
  - "AWS-based RDS operations dashboard"
  - "AI SDLC governance framework"
  - "Python 3.11 for Lambda"
  - "TypeScript for frontend/BFF"
  - "AWS CDK for infrastructure"
  - "Cognito with PKCE authentication"
```

This helps CodeRabbit give context-aware suggestions!

## 🎯 What CodeRabbit Will Check

### Security (Critical Priority)
- ✅ Hardcoded secrets/credentials
- ✅ SQL injection vulnerabilities
- ✅ XSS vulnerabilities
- ✅ Authentication bypasses
- ✅ Improper IAM permissions
- ✅ Exposed sensitive data

### Code Quality (High Priority)
- ✅ Missing error handling
- ✅ Missing input validation
- ✅ Performance bottlenecks
- ✅ Hardcoded configuration
- ✅ Missing TypeScript types
- ✅ Deprecated API usage

### Best Practices (Medium Priority)
- ✅ Code duplication
- ✅ Missing tests
- ✅ Unclear naming
- ✅ Missing documentation
- ✅ AWS best practices
- ✅ React best practices

### Style (Low Priority)
- ✅ Code style consistency
- ✅ Minor optimizations
- ✅ Comment typos

## 💬 Interacting with CodeRabbit

### Commands You Can Use

In PR comments, you can:

```
@coderabbit review
# Request a full review

@coderabbit resolve
# Mark all comments as resolved

@coderabbit pause
# Pause reviews temporarily

@coderabbit resume
# Resume reviews

@coderabbit help
# Show available commands
```

### Responding to Feedback

#### Option 1: Apply Suggestion (One Click)
CodeRabbit provides code suggestions you can apply directly:
```
[Apply Suggestion] button
```

#### Option 2: Explain Why It's Okay
```
@coderabbit This is intentional because we need to support legacy API.
```

#### Option 3: Fix and Request Re-Review
```bash
# Fix the issue
git add .
git commit -m "fix: Address CodeRabbit feedback"
git push

# CodeRabbit automatically re-reviews
```

## 📈 Example Review

### Before CodeRabbit
```typescript
// src/auth/login.ts
export async function login(username, password) {
  const user = await db.query(
    `SELECT * FROM users WHERE username='${username}'`
  );
  
  if (user && user.password === password) {
    return { token: "abc123" };
  }
}
```

### CodeRabbit Comments

**Comment 1 (Critical):**
```
🔴 SQL Injection Vulnerability

Line 3: Using string interpolation in SQL query allows SQL injection attacks.

Suggestion:
const user = await db.query(
  'SELECT * FROM users WHERE username = $1',
  [username]
);
```

**Comment 2 (Critical):**
```
🔴 Insecure Password Comparison

Line 6: Plain text password comparison is insecure.

Suggestion:
import bcrypt from 'bcrypt';

if (user && await bcrypt.compare(password, user.passwordHash)) {
  // ...
}
```

**Comment 3 (High):**
```
🟠 Missing TypeScript Types

Function parameters lack type annotations.

Suggestion:
export async function login(
  username: string, 
  password: string
): Promise<{ token: string } | null>
```

**Comment 4 (High):**
```
🟠 Hardcoded Token

Line 7: Token should be generated securely.

Suggestion:
import jwt from 'jsonwebtoken';

return { 
  token: jwt.sign({ userId: user.id }, process.env.JWT_SECRET) 
};
```

### After Fixes
```typescript
// src/auth/login.ts
import bcrypt from 'bcrypt';
import jwt from 'jsonwebtoken';
import { db } from './database';

interface LoginResult {
  token: string;
}

export async function login(
  username: string,
  password: string
): Promise<LoginResult | null> {
  try {
    const user = await db.query(
      'SELECT * FROM users WHERE username = $1',
      [username]
    );
    
    if (!user) {
      return null;
    }
    
    const isValid = await bcrypt.compare(password, user.passwordHash);
    
    if (!isValid) {
      return null;
    }
    
    const token = jwt.sign(
      { userId: user.id },
      process.env.JWT_SECRET!,
      { expiresIn: '1h' }
    );
    
    return { token };
  } catch (error) {
    logger.error('Login failed:', error);
    throw new AuthenticationError('Login failed');
  }
}
```

**CodeRabbit Response:**
```
✅ All issues resolved! Great job on the security improvements.

The code now:
- Uses parameterized queries (prevents SQL injection)
- Compares passwords securely with bcrypt
- Has proper TypeScript types
- Generates secure JWT tokens
- Includes error handling

Ready to merge! 🎉
```

## 🎓 Learning from CodeRabbit

CodeRabbit helps you learn by:

1. **Explaining Why**
   - Not just "fix this"
   - Explains the security/performance impact

2. **Providing Examples**
   - Shows correct implementation
   - Links to documentation

3. **Being Consistent**
   - Enforces same standards across codebase
   - Helps team align on best practices

## 🔧 Customizing for Your Needs

### Want More/Fewer Comments?

Edit `.coderabbit.yaml`:

```yaml
# More thorough (current setting)
profile: "assertive"

# Less aggressive
profile: "chill"
```

### Want to Focus on Specific Areas?

```yaml
focus_areas:
  - security      # Always check
  - performance   # Always check
  # - testing     # Comment out to skip
```

### Want to Ignore Certain Files?

```yaml
ignore:
  - "**/test-data/**"
  - "**/mock-*.ts"
  - "**/legacy/**"
```

## 📞 Getting Help

### CodeRabbit Not Working?

1. **Check Installation**
   - Go to: https://github.com/apps/coderabbit-ai
   - Verify it's installed on your repo

2. **Check Permissions**
   - CodeRabbit needs read/write access to PRs
   - Check GitHub App settings

3. **Check Configuration**
   - Validate `.coderabbit.yaml` syntax
   - Use: https://www.yamllint.com/

4. **Contact Support**
   - Email: support@coderabbit.ai
   - Docs: https://docs.coderabbit.ai

## 🎉 You're Ready!

CodeRabbit is now:
- ✅ Installed on your repository
- ✅ Configured for your project
- ✅ Ready to review PRs
- ✅ Helping you ship better code

Just create a PR and watch it work!

---

**Next Steps:**
1. Install CodeRabbit app
2. Create a test PR
3. Review CodeRabbit's feedback
4. Start using it for real PRs

**Documentation:**
- Full explanation: `docs/CODERABBIT-EXPLAINED.md`
- Configuration: `.coderabbit.yaml`
- CodeRabbit website: https://coderabbit.ai
- CodeRabbit docs: https://docs.coderabbit.ai

---

## 🔄 Alternative AI Code Review Tools

If CodeRabbit is not available or you want to try alternatives:

### 1. **GitHub Copilot for Pull Requests**
- **URL**: https://github.com/features/copilot
- **What it does**: AI-powered code suggestions and PR summaries
- **Cost**: $10/month (included with Copilot subscription)
- **Setup**: Enable in GitHub settings

### 2. **Amazon CodeGuru Reviewer**
- **URL**: https://aws.amazon.com/codeguru/
- **What it does**: AWS-native code review with security scanning
- **Cost**: Pay per line of code reviewed
- **Best for**: AWS-heavy projects (like yours!)
- **Setup**: Enable in AWS Console

### 3. **SonarCloud**
- **URL**: https://sonarcloud.io
- **What it does**: Code quality and security analysis
- **Cost**: Free for open source
- **Setup**: Already configured in your `.coderabbit.yaml`!

### 4. **Snyk Code**
- **URL**: https://snyk.io/product/snyk-code/
- **What it does**: Security-focused code analysis
- **Cost**: Free tier available
- **Setup**: Already configured in your `.coderabbit.yaml`!

### 5. **DeepSource**
- **URL**: https://deepsource.io
- **What it does**: Automated code review and analysis
- **Cost**: Free for open source
- **Setup**: Connect via GitHub

### Quick Comparison

| Tool | AI-Powered | Security | Performance | Cost | Best For |
|------|-----------|----------|-------------|------|----------|
| **CodeRabbit** | ✅ Yes | ✅ Yes | ✅ Yes | Free tier | All-in-one |
| **Copilot PR** | ✅ Yes | ⚠️ Basic | ⚠️ Basic | $10/mo | GitHub users |
| **CodeGuru** | ✅ Yes | ✅ Yes | ✅ Yes | Pay-per-use | AWS projects |
| **SonarCloud** | ❌ No | ✅ Yes | ✅ Yes | Free | Quality focus |
| **Snyk** | ⚠️ Partial | ✅ Yes | ❌ No | Free tier | Security focus |

### Using Multiple Tools

You can use multiple tools together:

```yaml
# Your .coderabbit.yaml already enables:
integrations:
  sonarcloud:
    enabled: true  # Code quality metrics
  snyk:
    enabled: true  # Security scanning
```

This gives you:
- **CodeRabbit**: AI-powered reviews
- **SonarCloud**: Deep quality analysis
- **Snyk**: Security vulnerability detection

---

## 📞 Need Help?

### CodeRabbit Not Available?

1. **Check Status**
   - Visit: https://status.coderabbit.ai
   - Check if service is operational

2. **Try Alternatives**
   - Use SonarCloud (already configured)
   - Use Snyk (already configured)
   - Try GitHub Copilot

3. **Manual Review**
   - Use local analysis: `./scripts/run-local-analysis.ps1`
   - Review with your team

### Configuration Issues?

Your `.coderabbit.yaml` is already set up and will work with:
- CodeRabbit (when available)
- SonarCloud (active)
- Snyk (active)
- Local tools (ESLint, Ruff, etc.)
