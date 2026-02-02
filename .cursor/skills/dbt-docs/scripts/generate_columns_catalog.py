#!/usr/bin/env python3
"""
Generate a consolidated YAML catalog of all columns and their descriptions.

Scans all YAML files in the models/ directory and extracts column names
and descriptions, creating a single catalog file for reference.

Usage:
    python scripts/generate_columns_catalog.py

Output:
    columns_catalog.yml in the repository root
"""

from __future__ import annotations

import os
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Tuple

try:
    import yaml
except ImportError:
    sys.stderr.write("PyYAML is required. Install with: pip install pyyaml\n")
    sys.exit(1)


def find_repo_root(start_dir: str) -> Path:
    """Find repository root by looking for dbt_project.yml."""
    current = Path(start_dir).resolve()
    for _ in range(10):
        if (current / "dbt_project.yml").exists():
            return current
        if current.parent == current:
            break
        current = current.parent
    return Path(start_dir).resolve()


SCRIPT_DIR = Path(__file__).parent
REPO_ROOT = find_repo_root(str(SCRIPT_DIR))
OUTPUT_PATH = REPO_ROOT / "columns_catalog.yml"


def is_yaml_file(path: str) -> bool:
    """Check if file is a YAML file."""
    lower = path.lower()
    return lower.endswith(".yml") or lower.endswith(".yaml")


def iter_yaml_files(base_dir: Path) -> Iterable[Path]:
    """Iterate over all YAML files in directory, excluding common non-model dirs."""
    skip_dirs = {"target", "dbt_packages", "dbt_internal_packages", ".git", ".venv", "venv", "__pycache__"}
    
    for root, dirs, files in os.walk(base_dir):
        dirs[:] = [d for d in dirs if d not in skip_dirs]
        for filename in files:
            if is_yaml_file(filename):
                yield Path(root) / filename


def safe_load_yaml(path: Path) -> Optional[Dict]:
    """Safely load a YAML file."""
    try:
        with open(path, "r", encoding="utf-8") as f:
            return yaml.safe_load(f)
    except Exception:
        return None


IN_THIS_TABLE_PATTERN = re.compile(r"\bin\s+this\s+table\s*:\s*", re.IGNORECASE)


def split_description(desc: str) -> Tuple[str, Optional[str]]:
    """Split description into base and 'In this table:' context."""
    if not isinstance(desc, str):
        return "", None
    
    match = IN_THIS_TABLE_PATTERN.search(desc)
    if not match:
        return desc.strip(), None
    
    base = desc[:match.start()].strip()
    context = desc[match.end():].strip()
    return base, (context if context else None)


def normalize_text(text: str) -> str:
    """Normalize whitespace in text."""
    if not text:
        return ""
    return re.sub(r"\s+", " ", text).strip()


def extract_columns_from_model(model: Dict[str, Any], model_name: str) -> List[Dict]:
    """Extract column information from a model definition."""
    columns = model.get("columns")
    if not isinstance(columns, list):
        return []
    
    results = []
    for col in columns:
        if not isinstance(col, dict):
            continue
        col_name = col.get("name")
        if not isinstance(col_name, str):
            continue
        
        desc = col.get("description", "")
        if not isinstance(desc, str):
            desc = ""
        
        base_desc, in_this = split_description(desc)
        results.append({
            "name": col_name,
            "description": normalize_text(base_desc),
            "in_this_table": in_this,
            "model": model_name,
        })
    
    return results


def extract_from_yaml(doc: Dict, yaml_path: Path) -> List[Dict]:
    """Extract column definitions from a YAML document."""
    if not isinstance(doc, dict):
        return []
    
    results = []
    
    # Handle models section
    models = doc.get("models", [])
    for model in (models if isinstance(models, list) else []):
        if not isinstance(model, dict):
            continue
        model_name = model.get("name", yaml_path.stem)
        results.extend(extract_columns_from_model(model, model_name))
    
    # Handle sources section
    sources = doc.get("sources", [])
    for source in (sources if isinstance(sources, list) else []):
        if not isinstance(source, dict):
            continue
        source_name = source.get("name", "")
        tables = source.get("tables", [])
        for table in (tables if isinstance(tables, list) else []):
            if not isinstance(table, dict):
                continue
            table_name = table.get("name", "")
            full_name = f"source.{source_name}.{table_name}"
            results.extend(extract_columns_from_model(table, full_name))
    
    return results


def consolidate(base_dir: Path) -> List[Dict[str, Any]]:
    """Consolidate all column definitions into a catalog."""
    index: Dict[str, Dict[str, Any]] = defaultdict(
        lambda: {"descriptions": Counter(), "models": []}
    )
    
    models_dir = base_dir / "models"
    if not models_dir.exists():
        print(f"Warning: models directory not found at {models_dir}")
        return []
    
    for yaml_path in iter_yaml_files(models_dir):
        doc = safe_load_yaml(yaml_path)
        if not doc:
            continue
        
        for col_info in extract_from_yaml(doc, yaml_path):
            col_name = col_info["name"]
            desc = col_info["description"]
            
            if desc:
                index[col_name]["descriptions"][desc] += 1
            
            index[col_name]["models"].append({
                "model": col_info["model"],
                "in_this_table": col_info["in_this_table"],
            })
    
    # Build catalog
    catalog = []
    for col_name in sorted(index.keys(), key=str.lower):
        data = index[col_name]
        
        # Get most common description
        if data["descriptions"]:
            main_desc = data["descriptions"].most_common(1)[0][0]
        else:
            main_desc = ""
        
        catalog.append({
            "name": col_name,
            "description": main_desc,
            "used_in": [m["model"] for m in data["models"]],
            "variations": len(data["descriptions"]),
        })
    
    return catalog


def main() -> int:
    """Main entry point."""
    catalog = consolidate(REPO_ROOT)
    
    if not catalog:
        print("No columns found to catalog.")
        return 0
    
    with open(OUTPUT_PATH, "w", encoding="utf-8") as f:
        yaml.safe_dump(catalog, f, sort_keys=False, allow_unicode=True, width=120)
    
    print(f"Wrote {len(catalog)} columns to: {OUTPUT_PATH}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
