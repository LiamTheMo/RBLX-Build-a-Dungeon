#!/usr/bin/env python3
"""Run the headless Luau specs under tests/luau.

Adapted from RBLX-Flintborn's tests/luau/run.py (same owner). Game modules are
written for Roblox: they `require(script.Parent.X)` and use Roblox datatypes.
Each spec runs as one generated bundle: prelude.luau (datatype stubs, a fake
instance tree and a require that resolves it), then every module under
src/shared, src/server and src/client as a loader function (only required
modules run), then the spec itself.

Only pure-logic modules are testable this way; anything touching Instances,
services or the network still needs a Studio playtest.

    python tests/luau/run.py                  # run every *.spec.luau with the `luau` CLI
    python tests/luau/run.py --bundle NAME    # print one spec's bundle (e.g. to run in Studio)

The `luau` CLI is managed by Aftman (aftman.toml). Without it, print a bundle
and run it in Studio's command bar or through the Studio MCP.
"""
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent

# Rojo mount points, keyed by the instance path game code sees.
MOUNTS = {
    ("ReplicatedStorage", "Shared"): ROOT / "src" / "shared",
    ("ServerScriptService", "Server"): ROOT / "src" / "server",
    # Client presentation data some specs cross-check (e.g. a colour per rarity).
    ("StarterPlayer", "StarterPlayerScripts", "Client"): ROOT / "src" / "client",
    ("ServerStorage", "TestSupport"): HERE / "support",
}


def module_entries():
    entries = []
    for prefix, folder in MOUNTS.items():
        if not folder.is_dir():
            continue
        for file in sorted(folder.rglob("*.luau")):
            # Entry-point scripts are not requirable modules.
            if file.name.endswith((".server.luau", ".client.luau")):
                continue
            parts = list(file.relative_to(folder).with_suffix("").parts)
            if parts[-1] == "init":
                parts = parts[:-1]
            entries.append((list(prefix) + parts, file.read_text(encoding="utf-8")))
    return entries


def build_bundle(spec: Path) -> str:
    chunks = [(HERE / "prelude.luau").read_text(encoding="utf-8")]
    for path, source in module_entries():
        chunks.append(
            "__defineModule({path}, function(script)\n{source}\nend)\n".format(
                path="{" + ", ".join(json.dumps(p) for p in path) + "}",
                source=source,
            )
        )
    chunks.append(
        "__runSpec({name}, function()\n{source}\nend)\n".format(
            name=json.dumps(spec.name), source=spec.read_text(encoding="utf-8")
        )
    )
    return "\n".join(chunks)


def main() -> int:
    specs = sorted(HERE.glob("*.spec.luau"))
    if len(sys.argv) == 2 and sys.argv[1] == "--studio":
        # Writes every bundle plus index.txt to build/specs/ for tests/luau/studio_runner.luau.
        out = ROOT / "build" / "specs"
        out.mkdir(parents=True, exist_ok=True)
        for old in out.glob("*.luau"):
            old.unlink()
        for spec in specs:
            (out / (spec.stem + ".bundle.luau")).write_text(build_bundle(spec), encoding="utf-8")
        (out / "index.txt").write_text("\n".join(s.stem + ".bundle.luau" for s in specs), encoding="utf-8")
        print(f"Wrote {len(specs)} bundles to {out}")
        return 0
    if len(sys.argv) == 3 and sys.argv[1] == "--bundle":
        matches = [s for s in specs if s.name.startswith(sys.argv[2])]
        if len(matches) != 1:
            print(f"Expected one spec matching {sys.argv[2]!r}, found {len(matches)}", file=sys.stderr)
            return 1
        sys.stdout.write(build_bundle(matches[0]))
        return 0

    luau = shutil.which("luau")
    if luau is None:
        print("luau CLI not found on PATH (run `aftman install`)", file=sys.stderr)
        return 1
    if not specs:
        print("No specs found", file=sys.stderr)
        return 1

    failed = 0
    with tempfile.TemporaryDirectory() as tmp:
        for spec in specs:
            bundle = Path(tmp) / (spec.stem + ".bundle.luau")
            bundle.write_text(build_bundle(spec), encoding="utf-8")
            result = subprocess.run([luau, str(bundle)], capture_output=True, text=True)
            sys.stdout.write(result.stdout)
            sys.stderr.write(result.stderr)
            if result.returncode != 0 or "SPEC FAILED" in result.stdout:
                failed += 1

    print(f"{len(specs) - failed}/{len(specs)} spec files passed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
