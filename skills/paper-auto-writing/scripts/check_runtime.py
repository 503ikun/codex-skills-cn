#!/usr/bin/env python3
"""Inspect a Linux, WSL, or remote runtime for AI-Scientist-v2 readiness."""

from __future__ import annotations

import argparse
import json
import os
import platform
import shutil
import subprocess
from pathlib import Path


REPO_MARKERS = (
    "launch_scientist_bfts.py",
    "ai_scientist/perform_ideation_temp_free.py",
)


def run_command(args: list[str]) -> tuple[bool, str]:
    try:
        completed = subprocess.run(
            args,
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError as exc:
        return False, str(exc)
    output = (completed.stdout or completed.stderr).strip()
    return completed.returncode == 0, output


def looks_like_repo(path: Path) -> bool:
    return all((path / marker).exists() for marker in REPO_MARKERS)


def find_repo(repo_path: str | None) -> Path | None:
    candidates: list[Path] = []
    if repo_path:
        candidates.append(Path(repo_path).expanduser())
    env_value = os.getenv("AI_SCIENTIST_V2_PATH")
    if env_value:
        candidates.append(Path(env_value).expanduser())
    cwd = Path.cwd()
    candidates.extend([cwd, *cwd.parents])
    home = Path.home()
    candidates.extend(
        [
            home / "AI-Scientist-v2",
            home / "source" / "AI-Scientist-v2",
            home / "src" / "AI-Scientist-v2",
            home / "projects" / "AI-Scientist-v2",
            home / "work" / "AI-Scientist-v2",
        ]
    )
    seen: set[Path] = set()
    for candidate in candidates:
        try:
            resolved = candidate.resolve()
        except OSError:
            continue
        if resolved in seen:
            continue
        seen.add(resolved)
        if looks_like_repo(resolved):
            return resolved
    return None


def detect_mode() -> str:
    system = platform.system().lower()
    release = platform.release().lower()
    if system == "linux" and "microsoft" in release:
        return "wsl"
    if system == "linux":
        return "remote-linux"
    if system == "windows":
        return "windows-prep"
    return system


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-path", help="Explicit AI-Scientist-v2 repository path.")
    parser.add_argument("--json", action="store_true", help="Print JSON output.")
    args = parser.parse_args()

    python_ok, python_version = run_command(["python", "--version"])
    nvidia_ok, nvidia_info = run_command(
        ["nvidia-smi", "--query-gpu=name,driver_version,memory.total", "--format=csv,noheader"]
    )
    repo = find_repo(args.repo_path)
    env_flags = {
        key: bool(os.getenv(key))
        for key in (
            "OPENAI_API_KEY",
            "GEMINI_API_KEY",
            "S2_API_KEY",
            "AWS_ACCESS_KEY_ID",
            "AWS_SECRET_ACCESS_KEY",
            "AWS_REGION_NAME",
        )
    }

    blockers: list[str] = []
    if not python_ok:
        blockers.append("Python was not found in PATH.")
    if not repo:
        blockers.append("AI-Scientist-v2 repository path was not found.")
    if not any(
        [
            env_flags["OPENAI_API_KEY"],
            env_flags["GEMINI_API_KEY"],
            env_flags["AWS_ACCESS_KEY_ID"],
        ]
    ):
        blockers.append("No supported model credentials were detected.")
    if detect_mode() in {"wsl", "remote-linux"} and not nvidia_ok:
        blockers.append("nvidia-smi was not available in this Linux runtime.")

    result = {
        "platform": platform.platform(),
        "mode": detect_mode(),
        "repoPath": str(repo) if repo else None,
        "python": {
            "found": python_ok or shutil.which("python") is not None,
            "version": python_version if python_ok else None,
        },
        "gpu": {
            "nvidiaSmi": nvidia_ok,
            "summary": [line for line in nvidia_info.splitlines() if line.strip()] if nvidia_ok else [],
        },
        "env": env_flags,
        "blockers": blockers,
    }

    if args.json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0

    print(f"Mode: {result['mode']}")
    print(f"Repo: {result['repoPath'] or 'not found'}")
    print(f"Python: {result['python']['version'] or 'not found'}")
    print(f"NVIDIA GPU visible: {result['gpu']['nvidiaSmi']}")
    if result["gpu"]["summary"]:
        for line in result["gpu"]["summary"]:
            print(f"  {line}")
    print("API keys:")
    for key, present in result["env"].items():
        print(f"  - {key}: {present}")
    if blockers:
        print("Blockers:")
        for item in blockers:
            print(f"  - {item}")
    else:
        print("Blockers: none detected.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
