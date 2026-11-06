#!/usr/bin/env python3
"""The registry's own native check (horizon-mods scripts/native_compat.py, `check`) on a file not yet submitted.

    python3 tools/registry_check.py REGISTRY_CHECKOUT FILE.hnmod --horizon latest --popular 20

Only "which versions are new" is replaced; everything else is the registry's code, as it runs on a form's pull request.
"""
import argparse
import sys
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("registry", type=Path)
parser.add_argument("file", type=Path)
parser.add_argument("--horizon", default="latest")
parser.add_argument("--popular", type=int, default=20)
args = parser.parse_args()

sys.path.insert(0, str(args.registry.resolve() / "scripts"))
import native_compat  # noqa: E402

bundle = native_compat.Bundle(args.file.read_bytes(), "submitted")
native_compat.new_versions = lambda base, head: [bundle]
sys.exit(native_compat.check(argparse.Namespace(base="", head="", horizon=args.horizon, popular=args.popular,
                                                no_compile=False)))
