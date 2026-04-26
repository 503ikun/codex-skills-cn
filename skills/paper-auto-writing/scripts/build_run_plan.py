#!/usr/bin/env python3
"""Generate a concrete AI-Scientist-v2 command plan without executing it."""

from __future__ import annotations

import argparse
import json
import os
import platform
from pathlib import Path


def detect_mode(explicit: str) -> str:
    if explicit != "auto":
        return explicit
    system = platform.system().lower()
    release = platform.release().lower()
    if system == "windows":
        return "windows-prep"
    if system == "linux" and "microsoft" in release:
        return "wsl"
    if system == "linux":
        return "remote-linux"
    return system


def to_linux_path(path: Path) -> str:
    value = str(path)
    if len(value) > 2 and value[1:3] == ":\\":
        drive = value[0].lower()
        tail = value[2:].replace("\\", "/")
        return f"/mnt/{drive}{tail}"
    return value.replace("\\", "/")


def guess_repo(repo_path: str | None) -> Path | None:
    candidates = []
    if repo_path:
        candidates.append(Path(repo_path).expanduser())
    env_repo = os.getenv("AI_SCIENTIST_V2_PATH")
    if env_repo:
        candidates.append(Path(env_repo).expanduser())
    home = Path.home()
    candidates.extend(
        [
            home / "source" / "AI-Scientist-v2",
            home / "src" / "AI-Scientist-v2",
            home / "projects" / "AI-Scientist-v2",
            home / "work" / "AI-Scientist-v2",
            home / "AI-Scientist-v2",
        ]
    )
    for candidate in candidates:
        if candidate.exists():
            return candidate.resolve()
    return None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", default="auto", choices=["auto", "windows-prep", "wsl", "remote-linux"])
    parser.add_argument("--repo-path", help="AI-Scientist-v2 repository path.")
    parser.add_argument("--topic-file", required=True, help="Path to the topic Markdown file.")
    parser.add_argument("--model", default="gpt-5.2-codex", help="Ideation model.")
    parser.add_argument("--max-num-generations", type=int, default=8)
    parser.add_argument("--num-reflections", type=int, default=3)
    parser.add_argument("--model-writeup", default="gpt-5.2-codex")
    parser.add_argument("--model-citation", default="gpt-5.2-codex")
    parser.add_argument("--model-review", default="gpt-5.2-codex")
    parser.add_argument("--model-agg-plots", default="gpt-5.2-codex")
    parser.add_argument("--num-cite-rounds", type=int, default=20)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    mode = detect_mode(args.mode)
    repo = guess_repo(args.repo_path)
    topic_path = Path(args.topic_file).expanduser().resolve()
    topic_stem = topic_path.stem
    idea_json = topic_path.with_suffix(".json")

    repo_display = str(repo) if repo else "<repo-path>"
    repo_linux = to_linux_path(repo) if repo else "<repo-path>"
    topic_linux = to_linux_path(topic_path)
    idea_linux = to_linux_path(idea_json)

    ideation_command_linux = (
        "python ai_scientist/perform_ideation_temp_free.py "
        f"--workshop-file '{topic_linux}' "
        f"--model {args.model} "
        f"--max-num-generations {args.max_num_generations} "
        f"--num-reflections {args.num_reflections}"
    )
    experiment_command_linux = (
        "python launch_scientist_bfts.py "
        f"--load_ideas '{idea_linux}' "
        "--load_code "
        "--add_dataset_ref "
        f"--model_writeup {args.model_writeup} "
        f"--model_citation {args.model_citation} "
        f"--model_review {args.model_review} "
        f"--model_agg_plots {args.model_agg_plots} "
        f"--num_cite_rounds {args.num_cite_rounds}"
    )

    if mode == "windows-prep":
        ideation_command = (
            "wsl bash -lc "
            f"\"cd '{repo_linux}' && {ideation_command_linux}\""
        )
        experiment_command = (
            "wsl bash -lc "
            f"\"cd '{repo_linux}' && {experiment_command_linux}\""
        )
    else:
        ideation_command = f'cd "{repo_display if mode == "remote-linux" else repo_linux}" && {ideation_command_linux}'
        experiment_command = f'cd "{repo_display if mode == "remote-linux" else repo_linux}" && {experiment_command_linux}'

    blockers = []
    if not topic_path.exists():
        blockers.append("Topic Markdown file does not exist yet.")
    if not repo:
        blockers.append("Repository path is not resolved. Pass --repo-path or set AI_SCIENTIST_V2_PATH.")
    if mode == "windows-prep":
        blockers.append("Current mode is preparation-only; validate Linux or WSL GPU readiness before execution.")

    result = {
        "mode": mode,
        "repoPath": str(repo) if repo else None,
        "topicFile": str(topic_path),
        "ideaFile": str(idea_json),
        "topicStem": topic_stem,
        "requiredEnv": ["OPENAI_API_KEY or another supported model credential", "Optional: S2_API_KEY"],
        "ideationCommand": ideation_command,
        "experimentCommand": experiment_command,
        "expectedOutputs": [
            str(idea_json),
            "experiments/<timestamp_idea>/logs/",
            "experiments/<timestamp_idea>/logs/0-run/unified_tree_viz.html",
            "experiments/<timestamp_idea>/<timestamp_idea>.pdf",
        ],
        "blockers": blockers,
    }

    if args.json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0

    print(f"Mode: {result['mode']}")
    print(f"Repo: {result['repoPath'] or 'not resolved'}")
    print(f"Topic: {result['topicFile']}")
    print(f"Idea JSON: {result['ideaFile']}")
    print("Required env:")
    for item in result["requiredEnv"]:
        print(f"  - {item}")
    print("Ideation command:")
    print(f"  {result['ideationCommand']}")
    print("Experiment command:")
    print(f"  {result['experimentCommand']}")
    print("Expected outputs:")
    for item in result["expectedOutputs"]:
        print(f"  - {item}")
    if blockers:
        print("Blockers:")
        for item in blockers:
            print(f"  - {item}")
    else:
        print("Blockers: none")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
