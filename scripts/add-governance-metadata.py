#!/usr/bin/env python3
"""
Script to add governance metadata to Lambda handler files.

This script scans all Lambda handler files and adds properly formatted
governance metadata blocks according to AI SDLC Governance Framework.
"""

import os
import sys
import re
from pathlib import Path

# Add lambda/shared to path
sys.path.insert(0, str(Path(__file__).parent.parent / 'lambda' / 'shared'))

from governance_metadata import add_metadata, format_metadata_block, extract_metadata


# Mapping of Lambda functions to their traceability
LAMBDA_METADATA = {
    'discovery/handler.py': {
        'traceability': 'REQ-1.1, REQ-1.2, REQ-9.1 → DESIGN-001 → TASK-2',
        'version': '1.1.0'
    },
    'cost-analyzer/handler.py': {
        'traceability': 'REQ-4.1, REQ-4.2, REQ-4.3, REQ-4.4, REQ-4.5 → DESIGN-001 → TASK-4',
        'version': '1.1.0'
    },
    'compliance-checker/handler.py': {
        'traceability': 'REQ-6.1, REQ-6.2, REQ-6.3, REQ-6.4, REQ-6.5 → DESIGN-001 → TASK-5',
        'version': '1.1.0'
    },
    'health-monitor/handler.py': {
        'traceability': 'REQ-5.1, REQ-5.2, REQ-5.3 → DESIGN-001 → TASK-6',
        'version': '1.1.0'
    },
    'cloudops-generator/handler.py': {
        'traceability': 'REQ-7.1, REQ-7.2, REQ-7.3 → DESIGN-001 → TASK-7',
        'version': '1.1.0'
    },
    'query-handler/handler.py': {
        'traceability': 'REQ-8.1, REQ-8.2, REQ-8.3 → DESIGN-001 → TASK-8',
        'version': '1.1.0'
    },
    'operations/handler.py': {
        'traceability': 'REQ-9.1, REQ-9.2, REQ-9.3 → DESIGN-001 → TASK-9',
        'version': '1.1.0'
    },
    'approval-workflow/handler.py': {
        'traceability': 'REQ-10.1, REQ-10.2, REQ-10.3 → DESIGN-001 → TASK-10',
        'version': '1.1.0'
    }
}


def process_handler_file(filepath: Path, metadata_config: dict):
    """Process a single handler file to add/update governance metadata."""
    
    print(f"Processing: {filepath}")
    
    # Read file content
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Check if metadata already exists
    existing_metadata = extract_metadata(content)
    
    if existing_metadata:
        print(f"  ✓ Metadata already exists (skipping)")
        return
    
    # Generate new metadata
    metadata = add_metadata(
        traceability=metadata_config['traceability'],
        version=metadata_config['version']
    )
    
    # Format as Python docstring addition
    metadata_block = format_metadata_block(metadata, comment_style='python')
    
    # Find the module docstring and add metadata to it
    # Pattern: Match triple-quoted docstring at start of file
    docstring_pattern = r'("""[\s\S]*?""")'
    match = re.search(docstring_pattern, content)
    
    if match:
        old_docstring = match.group(1)
        # Remove closing quotes, add metadata, add closing quotes
        new_docstring = old_docstring[:-3] + '\n\nGovernance Metadata:\n' + \
                       '{\n' + \
                       f'  "generated_by": "{metadata["generated_by"]}",\n' + \
                       f'  "timestamp": "{metadata["timestamp"]}",\n' + \
                       f'  "version": "{metadata["version"]}",\n' + \
                       f'  "policy_version": "{metadata["policy_version"]}",\n' + \
                       f'  "traceability": "{metadata["traceability"]}",\n' + \
                       f'  "review_status": "{metadata["review_status"]}",\n' + \
                       f'  "risk_level": "{metadata["risk_level"]}",\n' + \
                       f'  "reviewed_by": {metadata["reviewed_by"]},\n' + \
                       f'  "approved_by": {metadata["approved_by"]}\n' + \
                       '}\n"""'
        
        content = content.replace(old_docstring, new_docstring, 1)
        
        # Write back
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(content)
        
        print(f"  ✓ Added governance metadata")
    else:
        print(f"  ✗ No docstring found")


def main():
    """Main execution function."""
    
    # Get lambda directory
    lambda_dir = Path(__file__).parent.parent / 'lambda'
    
    if not lambda_dir.exists():
        print(f"Error: Lambda directory not found: {lambda_dir}")
        return 1
    
    print("Adding governance metadata to Lambda handlers...\n")
    
    processed = 0
    for relative_path, metadata_config in LAMBDA_METADATA.items():
        filepath = lambda_dir / relative_path
        
        if filepath.exists():
            process_handler_file(filepath, metadata_config)
            processed += 1
        else:
            print(f"Warning: File not found: {filepath}")
    
    print(f"\n✓ Processed {processed} handler files")
    return 0


if __name__ == '__main__':
    sys.exit(main())
