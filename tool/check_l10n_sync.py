#!/usr/bin/env python3
"""Compare Flutter .arb localization files against the English template.

Detects:
  - Missing keys (in app_en.arb but not in the target file)
  - Outdated translations (English changed since git base, target not updated)
  - Placeholder mismatches (variables in {var} differing from English)
  - Orphaned keys (in target file but deleted from English)
  - Untranslated / empty strings

Designed as a helper for AI agents and human developers:
  - Default: concise human-readable summary table
  - --todo: actionable list of items needing translation or fix
  - --batch N --batch-size M: paginates large sets of missing keys for LLM context limits
  - --json: full structured report for programmatic consumption
  - --export-missing <file>: exports missing keys as JSON for translation
  - --apply <file>: applies translated JSON into target .arb in template order
  - --init <lang>: creates a new empty app_<lang>.arb

Usage:
  python3 tool/check_l10n_sync.py
  python3 tool/check_l10n_sync.py --lang de
  python3 tool/check_l10n_sync.py --lang de --batch 1 --batch-size 50
  python3 tool/check_l10n_sync.py --lang de --apply de_batch1.json
"""
import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

L10N_DIR = Path('lib/l10n')
TEMPLATE_FILE = L10N_DIR / 'app_en.arb'

# ICU placeholder extraction:
# Matches selector variables in {var, plural, ...} or {var, select, ...}
ICU_SELECTOR_RE = re.compile(r'\{(\w+)\s*,\s*(?:plural|select)\s*,')
# Strips ICU branch selectors like "=1{", "other{", "few{" so branch tags aren't counted as variables
ICU_BRANCH_RE = re.compile(r'(?:=\d+|zero|one|two|few|many|other)\s*\{')
# Matches standard variables in {var}
PLAIN_VAR_RE = re.compile(r'\{(\w+)\}')


def extract_placeholders(text: str, meta_placeholders: dict[str, Any] | None = None) -> set[str]:
    """Extract all placeholder variable names required by the text."""
    if meta_placeholders:
        return set(meta_placeholders.keys())
    if not isinstance(text, str):
        return set()

    vars_found: set[str] = set()
    for m in ICU_SELECTOR_RE.finditer(text):
        vars_found.add(m.group(1))

    cleaned = ICU_BRANCH_RE.sub('', text)
    for m in PLAIN_VAR_RE.finditer(cleaned):
        vars_found.add(m.group(1))

    return vars_found


def load_arb_raw(path: Path) -> dict[str, Any]:
    """Load ARB file preserving key order."""
    if not path.exists():
        return {}
    with open(path, encoding='utf-8') as f:
        return json.load(f)


def load_arb_from_git(ref: str, path: Path) -> dict[str, Any]:
    """Load ARB file from a git ref."""
    shown = subprocess.run(
        ['git', 'show', f'{ref}:{path.as_posix()}'],
        capture_output=True,
        text=True,
    )
    if shown.returncode != 0:
        return {}
    try:
        return json.loads(shown.stdout)
    except json.JSONDecodeError:
        return {}


def get_template_keys(arb_data: dict[str, Any]) -> list[str]:
    """Return regular message keys (excluding metadata @keys and @@locale) in order."""
    return [k for k in arb_data if not k.startswith('@')]


def find_target_files(requested_lang: str | None = None) -> list[Path]:
    """Find all target .arb files or match a requested language."""
    if not L10N_DIR.exists():
        return []

    if requested_lang:
        # Check if argument is a direct path or language code
        if requested_lang.endswith('.arb'):
            p = Path(requested_lang)
            return [p]
        target = L10N_DIR / f'app_{requested_lang}.arb'
        return [target]

    # Discover all app_*.arb files except app_en.arb
    files = sorted(
        p for p in L10N_DIR.glob('app_*.arb')
        if p.name != 'app_en.arb'
    )
    return files


def analyze_language(
    target_path: Path,
    template_data: dict[str, Any],
    template_git: dict[str, Any],
    base_ref: str,
) -> dict[str, Any]:
    """Analyze a single language against the template."""
    lang_code = target_path.stem.replace('app_', '')
    target_exists = target_path.exists()
    target_data = load_arb_raw(target_path) if target_exists else {}
    target_git = load_arb_from_git(base_ref, target_path) if target_exists else {}

    template_keys = get_template_keys(template_data)
    target_keys = set(get_template_keys(target_data))

    missing: list[dict[str, Any]] = []
    outdated: list[dict[str, Any]] = []
    placeholder_mismatch: list[dict[str, Any]] = []
    orphaned: list[str] = sorted(list(target_keys - set(template_keys)))
    up_to_date_count = 0

    for key in template_keys:
        en_val = template_data[key]
        meta = template_data.get(f'@{key}', {})
        meta_placeholders = meta.get('placeholders') if isinstance(meta, dict) else None
        description = meta.get('description', '') if isinstance(meta, dict) else ''
        expected_placeholders = extract_placeholders(en_val, meta_placeholders)

        if key not in target_data:
            missing.append({
                'key': key,
                'en': en_val,
                'description': description,
                'placeholders': sorted(list(expected_placeholders)),
            })
            continue

        tgt_val = target_data[key]

        # Check placeholder consistency
        tgt_placeholders = extract_placeholders(tgt_val)
        if expected_placeholders != tgt_placeholders:
            placeholder_mismatch.append({
                'key': key,
                'en': en_val,
                'target': tgt_val,
                'expected_placeholders': sorted(list(expected_placeholders)),
                'actual_placeholders': sorted(list(tgt_placeholders)),
                'missing_placeholders': sorted(list(expected_placeholders - tgt_placeholders)),
                'unexpected_placeholders': sorted(list(tgt_placeholders - expected_placeholders)),
            })
            continue

        # Check if outdated vs git base
        # If English changed in git base, but target translation remained identical to git base
        if template_git and key in template_git:
            en_base_val = template_git[key]
            if en_base_val != en_val:
                tgt_base_val = target_git.get(key)
                if tgt_base_val == tgt_val:
                    outdated.append({
                        'key': key,
                        'en_new': en_val,
                        'en_old': en_base_val,
                        'target': tgt_val,
                        'description': description,
                        'placeholders': sorted(list(expected_placeholders)),
                    })
                    continue

        up_to_date_count += 1

    total = len(template_keys)
    coverage = (up_to_date_count / total * 100) if total > 0 else 0.0

    return {
        'lang': lang_code,
        'path': target_path.as_posix(),
        'exists': target_exists,
        'summary': {
            'total_template': total,
            'up_to_date': up_to_date_count,
            'coverage_pct': round(coverage, 2),
            'missing': len(missing),
            'outdated': len(outdated),
            'placeholder_mismatches': len(placeholder_mismatch),
            'orphaned': len(orphaned),
        },
        'missing': missing,
        'outdated': outdated,
        'placeholder_mismatches': placeholder_mismatch,
        'orphaned': orphaned,
    }


def format_summary_table(reports: list[dict[str, Any]]) -> str:
    """Format summary as a clean table."""
    lines = []
    lines.append('Locale | Status / File           | Coverage | Missing | Outdated | Mismatch | Orphan')
    lines.append('-------|-------------------------|----------|---------|----------|----------|-------')
    for rep in reports:
        s = rep['summary']
        exists = rep['exists']
        status = rep['path'] if exists else f"{rep['path']} (NOT CREATED)"
        lines.append(
            f"{rep['lang']:<6} | {status:<23} | {s['coverage_pct']:>6.1f}%  | "
            f"{s['missing']:>7} | {s['outdated']:>8} | {s['placeholder_mismatches']:>8} | {s['orphaned']:>6}"
        )
    return '\n'.join(lines)


def format_todo(
    report: dict[str, Any],
    batch: int | None = None,
    batch_size: int = 50,
) -> str:
    """Format actionable items in a concise layout optimized for AI reading."""
    lines = []
    lang = report['lang']
    path = report['path']
    s = report['summary']

    lines.append(f'=== Translation Tasks: [{lang}] ({path}) ===')
    lines.append(
        f"Progress: {s['up_to_date']}/{s['total_template']} ({s['coverage_pct']}%) | "
        f"Missing: {s['missing']} | Outdated: {s['outdated']} | Mismatches: {s['placeholder_mismatches']}"
    )

    # Missing keys pagination
    missing_items = report['missing']
    total_missing = len(missing_items)

    if missing_items:
        lines.append('')
        if batch is not None:
            start = (batch - 1) * batch_size
            end = min(start + batch_size, total_missing)
            batch_items = missing_items[start:end]
            total_batches = (total_missing + batch_size - 1) // batch_size
            lines.append(f'--- MISSING KEYS (Batch {batch}/{total_batches}, items {start + 1}-{end} of {total_missing}) ---')
        else:
            batch_items = missing_items
            lines.append(f'--- MISSING KEYS ({total_missing} items) ---')

        for item in batch_items:
            lines.append(f"Key: {item['key']}")
            lines.append(f"  EN: {item['en']}")
            if item['description']:
                lines.append(f"  Context: {item['description']}")
            if item['placeholders']:
                lines.append(f"  Placeholders: {', '.join(item['placeholders'])}")
            lines.append('')

    if report['outdated']:
        lines.append('--- OUTDATED KEYS (English source changed in git) ---')
        for item in report['outdated']:
            lines.append(f"Key: {item['key']}")
            lines.append(f"  Old EN:  {item['en_old']}")
            lines.append(f"  New EN:  {item['en_new']}")
            lines.append(f"  Current: {item['target']}")
            if item['description']:
                lines.append(f"  Context: {item['description']}")
            lines.append('')

    if report['placeholder_mismatches']:
        lines.append('--- PLACEHOLDER MISMATCHES (Requires manual fix) ---')
        for item in report['placeholder_mismatches']:
            lines.append(f"Key: {item['key']}")
            lines.append(f"  EN:     {item['en']}")
            lines.append(f"  Target: {item['target']}")
            lines.append(f"  Expected: {item['expected_placeholders']}")
            lines.append(f"  Actual:   {item['actual_placeholders']}")
            if item['missing_placeholders']:
                lines.append(f"  Missing in target: {item['missing_placeholders']}")
            if item['unexpected_placeholders']:
                lines.append(f"  Unexpected in target: {item['unexpected_placeholders']}")
            lines.append('')

    if report['orphaned']:
        lines.append(f"--- ORPHANED KEYS ({len(report['orphaned'])} keys no longer in English) ---")
        lines.append(', '.join(report['orphaned'][:30]))
        if len(report['orphaned']) > 30:
            lines.append(f"... and {len(report['orphaned']) - 30} more")
        lines.append('')

    return '\n'.join(lines)


def write_arb_file(
    path: Path,
    locale: str,
    target_data: dict[str, Any],
    template_data: dict[str, Any],
) -> None:
    """Write .arb file preserving template ordering and inline metadata formatting."""
    lines = ['{', f'  "@@locale": "{locale}",', '']

    template_keys = get_template_keys(template_data)

    # Write keys in template order
    for key in template_keys:
        if key not in target_data:
            continue

        val = target_data[key]
        encoded_val = json.dumps(val, ensure_ascii=False)
        lines.append(f'  "{key}": {encoded_val},')

        # If template had @key metadata with placeholders, carry placeholders metadata
        meta_key = f'@{key}'
        if meta_key in template_data:
            meta = template_data[meta_key]
            if isinstance(meta, dict) and 'placeholders' in meta:
                # Keep compact single-line format:
                meta_compact = {'placeholders': meta['placeholders']}
                lines.append(f'  "{meta_key}": {json.dumps(meta_compact, ensure_ascii=False)},')

    # Remove trailing comma from last non-empty line before closing bracket
    for i in range(len(lines) - 1, -1, -1):
        if lines[i].strip():
            if lines[i].endswith(','):
                lines[i] = lines[i][:-1]
            break

    lines.append('}\n')

    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines))


def apply_translations(
    target_path: Path,
    trans_file: Path,
    template_data: dict[str, Any],
) -> int:
    """Apply translated key-value pairs from a JSON file to target .arb file."""
    if not trans_file.exists():
        print(f"Error: translations file {trans_file} not found.", file=sys.stderr)
        return 1

    with open(trans_file, encoding='utf-8') as f:
        new_translations = json.load(f)

    # Support both flat { "key": "val" } and structured { "key": { "target": "val" } }
    flat_trans: dict[str, str] = {}
    for k, v in new_translations.items():
        if k.startswith('@'):
            continue
        if isinstance(v, str):
            flat_trans[k] = v
        elif isinstance(v, dict) and 'target' in v:
            flat_trans[k] = v['target']

    lang_code = target_path.stem.replace('app_', '')
    target_data = load_arb_raw(target_path)

    # Validate placeholders before saving
    errors = []
    for key, val in flat_trans.items():
        if key not in template_data:
            print(f"Warning: key '{key}' does not exist in English template, skipping.")
            continue
        en_val = template_data[key]
        meta = template_data.get(f'@{key}', {})
        meta_placeholders = meta.get('placeholders') if isinstance(meta, dict) else None
        expected = extract_placeholders(en_val, meta_placeholders)
        actual = extract_placeholders(val)
        if expected != actual:
            errors.append(f"  {key}: expected {expected}, got {actual}")

    if errors:
        print("Error: placeholder validation failed for translated keys:", file=sys.stderr)
        for err in errors:
            print(err, file=sys.stderr)
        print("Aborting apply without modifying target file.", file=sys.stderr)
        return 1

    # Merge
    applied_count = 0
    for key, val in flat_trans.items():
        if key in template_data:
            target_data[key] = val
            applied_count += 1

    write_arb_file(target_path, lang_code, target_data, template_data)
    print(f"Successfully applied {applied_count} translation(s) to {target_path}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--template', default=TEMPLATE_FILE.as_posix(), help='template ARB file (default: lib/l10n/app_en.arb)')
    parser.add_argument('--lang', help='specific language code or file (e.g. de, fr, es, pl)')
    parser.add_argument('--base', default='dev', help='git base ref to detect outdated translations (default: dev)')
    parser.add_argument('--init', help='initialize empty app_<lang>.arb file for the given language code')
    parser.add_argument('--todo', action='store_true', help='print detailed actionable items needing translation')
    parser.add_argument('--batch', type=int, help='batch index for missing keys (1-based)')
    parser.add_argument('--batch-size', type=int, default=50, help='batch size for --batch (default: 50)')
    parser.add_argument('--json', action='store_true', help='output full report in JSON format')
    parser.add_argument('--export-missing', help='file path to export missing keys as JSON')
    parser.add_argument('--apply', help='JSON file with translations to merge into target .arb')
    args = parser.parse_args()

    template_path = Path(args.template)
    if not template_path.exists():
        print(f"Error: template file {template_path} not found.", file=sys.stderr)
        return 1

    template_data = load_arb_raw(template_path)
    template_git = load_arb_from_git(args.base, template_path)

    # Handle --init
    if args.init:
        target_path = L10N_DIR / f'app_{args.init}.arb'
        if target_path.exists():
            print(f"File {target_path} already exists.")
            return 0
        write_arb_file(target_path, args.init, {}, template_data)
        print(f"Initialized empty {target_path} with locale '{args.init}'.")
        return 0

    # Handle --apply
    if args.apply:
        if not args.lang:
            print("Error: --apply requires --lang (e.g. --lang de).", file=sys.stderr)
            return 1
        target_path = L10N_DIR / f'app_{args.lang}.arb'
        return apply_translations(target_path, Path(args.apply), template_data)

    target_files = find_target_files(args.lang)
    if not target_files and args.lang:
        target_files = [L10N_DIR / f'app_{args.lang}.arb']

    reports = [
        analyze_language(tf, template_data, template_git, args.base)
        for tf in target_files
    ]

    # Handle --export-missing
    if args.export_missing:
        if len(reports) != 1:
            print("Error: --export-missing requires specifying exactly one language via --lang.", file=sys.stderr)
            return 1
        export_data = {
            item['key']: {
                'en': item['en'],
                'description': item['description'],
                'placeholders': item['placeholders'],
            }
            for item in reports[0]['missing']
        }
        with open(args.export_missing, 'w', encoding='utf-8') as f:
            json.dump(export_data, f, indent=2, ensure_ascii=False)
        print(f"Exported {len(export_data)} missing key(s) to {args.export_missing}")
        return 0

    if args.json:
        print(json.dumps(reports if len(reports) > 1 else reports[0], indent=2, ensure_ascii=False))
        return 0

    if args.todo or args.batch is not None:
        for rep in reports:
            print(format_todo(rep, batch=args.batch, batch_size=args.batch_size))
        return 0

    # Default output: summary table + brief issues
    print(format_summary_table(reports))

    has_issues = False
    for rep in reports:
        s = rep['summary']
        if s['missing'] > 0 or s['outdated'] > 0 or s['placeholder_mismatches'] > 0:
            has_issues = True
            print(f"\n[{rep['lang']}] {s['missing']} missing, {s['outdated']} outdated, {s['placeholder_mismatches']} placeholder errors.")
            print(f"  Run with --lang {rep['lang']} --todo (or --batch 1) to inspect actionable items.")

    return 1 if has_issues else 0


if __name__ == '__main__':
    sys.exit(main())
