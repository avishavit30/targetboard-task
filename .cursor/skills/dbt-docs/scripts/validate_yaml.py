#!/usr/bin/env python3
"""
Validate dbt model YAML documentation files.

Checks:
- YAML syntax is valid
- Column names match SQL output (requires SQL file path)
- All columns have descriptions
- Descriptions with colons are properly quoted
- No stale columns (in YAML but not in SQL)

Usage:
    python scripts/validate_yaml.py <yaml_file>
    python scripts/validate_yaml.py <yaml_file> --sql <sql_file>

Examples:
    python scripts/validate_yaml.py models/staging/_staging.yml
    python scripts/validate_yaml.py models/staging/_staging.yml --sql models/staging/stg_issues.sql
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path
from typing import Dict, List, Optional, Set

try:
    import yaml
except ImportError:
    sys.stderr.write("PyYAML is required. Install with: pip install pyyaml\n")
    sys.exit(1)


def load_yaml(path: Path) -> Optional[Dict]:
    """Load and parse YAML file."""
    try:
        with open(path, "r", encoding="utf-8") as f:
            return yaml.safe_load(f)
    except yaml.YAMLError as e:
        print(f"❌ YAML syntax error: {e}")
        return None
    except Exception as e:
        print(f"❌ Error reading file: {e}")
        return None


def extract_sql_columns(sql_path: Path) -> Set[str]:
    """
    Extract column names from SQL file's final SELECT statement.
    
    This is a simplified parser - it looks for the last SELECT and extracts
    column aliases (after AS) or column names.
    """
    try:
        with open(sql_path, "r", encoding="utf-8") as f:
            sql_content = f.read()
    except Exception as e:
        print(f"Warning: Could not read SQL file: {e}")
        return set()
    
    # Remove comments
    sql_content = re.sub(r"--.*$", "", sql_content, flags=re.MULTILINE)
    sql_content = re.sub(r"/\*.*?\*/", "", sql_content, flags=re.DOTALL)
    
    # Find the last SELECT statement (simplified approach)
    # Look for SELECT ... FROM pattern
    select_pattern = r"select\s+(.*?)\s+from"
    matches = list(re.finditer(select_pattern, sql_content, re.IGNORECASE | re.DOTALL))
    
    if not matches:
        print("Warning: Could not find SELECT statement in SQL")
        return set()
    
    # Use the last SELECT (typically the final output)
    last_select = matches[-1].group(1)
    
    columns = set()
    # Split by comma, handling nested parentheses
    depth = 0
    current = ""
    for char in last_select:
        if char == "(":
            depth += 1
            current += char
        elif char == ")":
            depth -= 1
            current += char
        elif char == "," and depth == 0:
            columns.add(parse_column_name(current))
            current = ""
        else:
            current += char
    
    if current.strip():
        columns.add(parse_column_name(current))
    
    # Remove empty strings
    columns.discard("")
    
    return columns


def parse_column_name(col_expr: str) -> str:
    """Extract column name/alias from a SELECT expression."""
    col_expr = col_expr.strip()
    
    # Handle "expression as alias" pattern
    as_match = re.search(r"\s+as\s+(\w+)\s*$", col_expr, re.IGNORECASE)
    if as_match:
        return as_match.group(1).lower()
    
    # Handle simple column reference (possibly with table prefix)
    simple_match = re.match(r"^[\w.]+$", col_expr)
    if simple_match:
        # Take the last part after any dots
        return col_expr.split(".")[-1].lower()
    
    # Fallback: return empty (will be filtered out)
    return ""


def get_yaml_columns(yaml_data: Dict, model_name: Optional[str] = None) -> Dict[str, Dict]:
    """
    Extract column definitions from YAML.
    
    Returns dict mapping column name to column info.
    """
    columns = {}
    
    models = yaml_data.get("models", [])
    for model in (models if isinstance(models, list) else []):
        if not isinstance(model, dict):
            continue
        
        # If model_name specified, only process that model
        if model_name and model.get("name") != model_name:
            continue
        
        for col in model.get("columns", []):
            if isinstance(col, dict) and "name" in col:
                columns[col["name"].lower()] = col
    
    return columns


def validate_descriptions(columns: Dict[str, Dict]) -> List[str]:
    """Check that all columns have descriptions."""
    issues = []
    
    for name, col in columns.items():
        desc = col.get("description", "")
        if not desc or not desc.strip():
            issues.append(f"Column '{name}' has no description")
    
    return issues


def validate_quoting(yaml_path: Path) -> List[str]:
    """Check for potential quoting issues in YAML."""
    issues = []
    
    try:
        with open(yaml_path, "r", encoding="utf-8") as f:
            lines = f.readlines()
    except Exception:
        return issues
    
    for i, line in enumerate(lines, 1):
        # Check for description lines with colons that might not be quoted
        if "description:" in line:
            # Get the value part after "description:"
            match = re.match(r"(\s*-?\s*description:\s*)(.+)", line)
            if match:
                value = match.group(2).strip()
                # If value contains a colon and doesn't start with a quote
                if ":" in value and not value.startswith(("'", '"', "|", ">")):
                    issues.append(f"Line {i}: Description contains ':' but may not be properly quoted")
    
    return issues


def main() -> int:
    """Main entry point."""
    parser = argparse.ArgumentParser(description="Validate dbt YAML documentation")
    parser.add_argument("yaml_file", type=Path, help="Path to YAML file")
    parser.add_argument("--sql", type=Path, help="Path to SQL file for column matching")
    parser.add_argument("--model", type=str, help="Specific model name to validate")
    
    args = parser.parse_args()
    
    if not args.yaml_file.exists():
        print(f"❌ YAML file not found: {args.yaml_file}")
        return 1
    
    print(f"Validating: {args.yaml_file}")
    print("=" * 60)
    
    all_issues = []
    
    # Load and parse YAML
    yaml_data = load_yaml(args.yaml_file)
    if yaml_data is None:
        return 1
    
    print("✅ YAML syntax is valid")
    
    # Get YAML columns
    yaml_columns = get_yaml_columns(yaml_data, args.model)
    print(f"📋 Found {len(yaml_columns)} columns in YAML")
    
    # Validate descriptions
    desc_issues = validate_descriptions(yaml_columns)
    all_issues.extend(desc_issues)
    
    # Check quoting
    quote_issues = validate_quoting(args.yaml_file)
    all_issues.extend(quote_issues)
    
    # If SQL file provided, check column matching
    if args.sql:
        if not args.sql.exists():
            print(f"⚠️  SQL file not found: {args.sql}")
        else:
            sql_columns = extract_sql_columns(args.sql)
            print(f"📋 Found {len(sql_columns)} columns in SQL")
            
            yaml_names = set(yaml_columns.keys())
            
            # Check for missing columns (in SQL but not in YAML)
            missing = sql_columns - yaml_names
            if missing:
                for col in sorted(missing):
                    all_issues.append(f"Column '{col}' is in SQL but not in YAML")
            
            # Check for stale columns (in YAML but not in SQL)
            stale = yaml_names - sql_columns
            if stale:
                for col in sorted(stale):
                    all_issues.append(f"Column '{col}' is in YAML but not in SQL (stale)")
    
    # Report results
    print("=" * 60)
    
    if not all_issues:
        print("✅ All validations passed!")
        return 0
    
    print(f"❌ Found {len(all_issues)} issue(s):\n")
    for issue in all_issues:
        print(f"  • {issue}")
    
    return 1


if __name__ == "__main__":
    sys.exit(main())
