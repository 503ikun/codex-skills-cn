# Runtime Modes

## Purpose

Use this reference to decide whether the current machine should only prepare a run or is capable of executing `AI-Scientist-v2`.

## windows-prep

Choose this mode when:

- the user is on Windows
- WSL2 is missing or unverified
- NVIDIA GPU / CUDA is missing or unverified
- the repository has not been prepared in a Linux environment

Allowed actions:

- inspect Python, WSL, API key, and repository availability
- create topic files
- generate commands
- document blockers and next steps

Avoid:

- claiming the full paper-generation pipeline will run on native Windows
- presenting Windows-only commands as the recommended execution path for the upstream repo

## wsl

Choose this mode when:

- the user is on Windows
- WSL2 is installed
- the repository is available inside WSL or can be mounted safely
- Linux-side Python and optional GPU tooling can be inspected

Preferred behavior:

- validate Linux Python and repository paths inside WSL
- generate WSL commands with `/mnt/...` paths when needed
- keep Windows-side file generation limited to preparation steps

## remote-linux

Choose this mode when:

- the user is already on Linux
- the runtime is a remote host or container
- GPU, CUDA, Python, and repository paths can be checked directly

Preferred behavior:

- treat the host as the execution environment
- generate direct bash commands
- surface missing API keys or repository files before showing the main run command

## Decision Rules

- If CUDA or `nvidia-smi` cannot be verified, do not market the environment as ready.
- If Python is available but the repository is missing, classify the system as preparation-only.
- If the repository exists but the idea JSON does not, ideation is the next step.
- If the idea JSON exists, the next step is the main `launch_scientist_bfts.py` plan.
