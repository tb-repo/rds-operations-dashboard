#!/usr/bin/env python3
"""
Fix CORS Headers in Lambda Handlers

Replaces insecure wildcard CORS "*" with secure origin validation.
"""

import re
from pathlib import Path

# Files to fix
files_to_fix = [
    'lambda/approval-workflow/handler.py',
    'lambda/cloudops-generator/handler.py',
    'lambda/operations/handler.py',
    'lambda/query-handler/handler.py',
]

# Pattern to match CORS headers with wildcard
patterns = [
    # Pattern 1: Single line with wildcard
    (
        r"'Access-Control-Allow-Origin': '\*'",
        "'Access-Control-Allow-Origin': get_cors_headers(event)['Access-Control-Allow-Origin']"
    ),
    # Pattern 2: Headers dict with wildcard
    (
        r"'headers': \{'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '\*'\}",
        "'headers': get_cors_headers(event)"
    ),
    # Pattern 3: Multi-line headers with wildcard
    (
        r"'headers': \{\s*'Content-Type': 'application/json',\s*'Access-Control-Allow-Origin': '\*'",
        "'headers': get_cors_headers(event)"
    ),
]

def fix_file(filepath: Path):
    """Fix CORS headers in a single file."""
    print(f"\nProcessing: {filepath}")
    
    if not filepath.exists():
        print(f"  ⚠ File not found: {filepath}")
        return False
    
    content = filepath.read_text()
    original_content = content
    
    # Check if cors_helper import already exists
    if 'from shared.cors_helper import' not in content:
        # Add import after other shared imports
        if 'from shared.config import Config' in content:
            content = content.replace(
                'from shared.config import Config',
                'from shared.config import Config\nfrom shared.cors_helper import get_cors_headers, is_preflight_request, handle_preflight'
            )
            print("  ✓ Added cors_helper import")
        elif 'from shared.logger import' in content:
            content = content.replace(
                'from shared.logger import',
                'from shared.cors_helper import get_cors_headers, is_preflight_request, handle_preflight\nfrom shared.logger import'
            )
            print("  ✓ Added cors_helper import")
    
    # Replace CORS patterns
    replacements = 0
    for pattern, replacement in patterns:
        matches = len(re.findall(pattern, content))
        if matches > 0:
            content = re.sub(pattern, replacement, content)
            replacements += matches
            print(f"  ✓ Replaced {matches} occurrences of pattern")
    
    # Additional cleanup for remaining wildcards
    remaining = content.count("'Access-Control-Allow-Origin': '*'")
    if remaining > 0:
        print(f"  ⚠ Warning: {remaining} wildcard CORS headers remain (manual review needed)")
    
    if content != original_content:
        filepath.write_text(content)
        print(f"  ✓ File updated ({replacements} replacements)")
        return True
    else:
        print("  - No changes needed")
        return False

def main():
    print("=" * 60)
    print("Fixing CORS Headers in Lambda Handlers")
    print("=" * 60)
    
    base_dir = Path(__file__).parent.parent
    fixed_count = 0
    
    for file_path in files_to_fix:
        full_path = base_dir / file_path
        if fix_file(full_path):
            fixed_count += 1
    
    print("\n" + "=" * 60)
    print(f"✓ Fixed {fixed_count} files")
    print("=" * 60)
    print("\nNext steps:")
    print("  1. Review the changes")
    print("  2. Set ALLOWED_ORIGINS environment variable in Lambda")
    print("  3. Test CORS with allowed origins")
    print("  4. Deploy updated Lambda functions")

if __name__ == '__main__':
    main()

