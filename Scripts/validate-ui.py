#!/usr/bin/env python3
"""Guard the app's ChunUI composition boundaries without inspecting dependencies."""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
source = root / "bili/Sources"
symbols = (source / "DesignSystem/PiliSymbols.swift").read_text()
known = set(re.findall(r'^\s*"([^"]+)":', symbols, re.M))
errors = []
for path in source.rglob("*.swift"):
    text = path.read_text()
    name = str(path.relative_to(root))
    for line_number, line in enumerate(text.splitlines(), 1):
        reason = None
        if re.search(r'\.(sheet|alert|confirmationDialog)\s*\(', line):
            reason = "Use the ChunUI presentation adapter"
        elif path.name != "PiliGlassPage.swift" and re.search(r'\b(Form|List)\s*[{(]', line):
            reason = "Use the common glass page adapter"
        elif path.name != "RootTabView.swift" and re.search(r'\bImage\(systemName:', line):
            reason = "Use a bundled Pika business icon"
        elif re.search(r'\.repeatForever\s*\(', line):
            reason = "Use bounded, accessibility-aware motion"
        if reason:
            errors.append(f"{name}:{line_number}: {reason}")
    for match in re.finditer(r'(?:systemName|systemImage|symbol):\s*"([^"\\]+)"', text):
        if match[1] not in known:
            errors.append(f"{name}: unmapped Pika icon alias {match[1]}")
if errors:
    raise SystemExit("\n".join(errors))
print("UI conventions passed: ChunUI presentations, glass pages, Pika aliases and bounded motion.")
