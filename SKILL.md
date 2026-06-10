---
name: codex-marker-pdf2html
description: Use when Codex should convert local PDFs or document files to HTML with the open source Marker/marker-pdf engine. Handles local marker discovery, optional installation, GPU selection when available, and output directory policy; also supports Markdown, JSON, and chunks when explicitly requested.
---

# Codex Marker PDF2HTML

Use this skill when the user asks Codex to convert PDFs or other Marker-supported local documents to HTML with `marker-pdf`. HTML is the default output. Use Markdown, JSON, or chunks only when the user explicitly asks for them.

## Core Workflow

1. Resolve the local Marker environment before conversion:

```powershell
.\scripts\resolve_marker.ps1
```

Run scripts from this skill directory. Use `powershell` or `pwsh`; pass `-NoProfile -ExecutionPolicy Bypass` when needed.

2. If Marker is not found, ask before installing because installation may write outside the workspace and download packages/models. Prefer:

```powershell
.\scripts\install_marker.ps1
```

Default install location is `%LOCALAPPDATA%\Codex\tools\marker-pdf\.venv`. The installer pins `marker-pdf==1.10.2` and also installs `psutil`.

3. Decide the output root:

- If the user specified an output path in chat, use it.
- Otherwise, use the cached `output_root` from the skill config.
- If no output root is configured yet, ask the user once whether to use the default Documents folder location:

```text
<User Documents>\MarkerOutput
```

If they agree, run conversion with `-UseDocumentsDefault`. If they choose another folder, pass `-OutputRoot <path>` and usually `-SetDefaultOutputRoot` so future runs use it.

4. Convert with:

```powershell
.\scripts\convert_with_marker.ps1 -InputPath "<pdf-or-folder>" -Format html
```

Use `-Format markdown`, `json`, or `chunks` only when requested. HTML is the default.

5. Verify output after conversion:

- Confirm the primary output file exists: `.html`, `.md`, or `.json`.
- Confirm `<stem>_meta.json` exists when Marker produced it.
- For HTML/Markdown, confirm extracted images remain in the same output directory.
- Read the beginning of the generated file to confirm title/body content looks plausible.

## Environment Discovery Policy

`resolve_marker.ps1` should be the first step. It checks, in order:

1. `MARKER_SINGLE_EXE` and `MARKER_PYTHON` environment variables.
2. Cached config at `%LOCALAPPDATA%\Codex\codex-marker-pdf2html\config.json`.
3. `marker_single` on `PATH`.
4. Common virtual environments such as `.marker-venv`, `.venv`, `venv`, and Codex tool installs.
5. Usable Python commands with `marker-pdf` installed.

When a valid Marker environment is found, cache it and reuse it on later runs.

## GPU Policy

`convert_with_marker.ps1` automatically checks the Marker Python environment with PyTorch:

- If `torch.cuda.is_available()` is true, set `TORCH_DEVICE=cuda`.
- If `CUDA_VISIBLE_DEVICES` is empty, set it to `0`.
- If CUDA is unavailable, run on CPU.
- If `nvidia-smi` sees a GPU but PyTorch CUDA is unavailable, report that fact and still use CPU.

Use `-ForceCpu` if the user explicitly asks not to use the GPU.

## Known Behaviors

- Marker may contact `models.datalab.to` to download or verify Surya models. If this fails because of sandbox or network restrictions, rerun with the required approval.
- CPU conversion can be slow. A 10-20 page paper may take several minutes.
- Prefer `marker_single.exe` over `marker.exe`; some installs have a batch entrypoint that fails without `psutil`.
- Marker may log "Saved markdown" even when `--output_format html` is used. Verify the actual output file extension instead of relying only on that log line.
- HTML output depends on same-directory extracted image files. Do not deliver only the `.html` file unless the user explicitly asks for a single-file derivative.

## Attribution

This skill is an orchestration layer for Codex. It does not vendor Marker. It uses the open source Marker/marker-pdf project by Datalab/Vik Paruchuri:

- Marker repository: https://github.com/datalab-to/marker
- Marker package: `marker-pdf`
- Marker license: GPL-3.0-or-later

When redistributing Marker itself, generated installers, or packaged environments that include Marker, preserve Marker copyright/license notices and comply with Marker license terms. For this skill repository, keep this attribution section in `SKILL.md`.

## Response Style

After conversion, give the user the primary output path, mention whether GPU or CPU was used, and note any required same-directory assets.
