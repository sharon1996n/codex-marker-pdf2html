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

Default install location is `%LOCALAPPDATA%\Codex\tools\marker-pdf\.venv`. The installer pins `marker-pdf==1.10.2` and also installs `psutil`. On Windows, it can use Codex's bundled Python when no system `python` or `uv` is available. If an NVIDIA GPU is detected and PyTorch CUDA is unavailable, it installs `torch==2.7.1+cu118` by default; pass `-SkipCudaTorch` only when CPU-only conversion is intended.

3. Decide the output root:

- If the user specified an output path in chat, use it.
- Otherwise, use the cached `output_root` from the skill config.
- If no output root is configured yet, ask the user once whether to use the default Documents folder location:

```text
<User Documents>\MarkerOutput
```

If they agree, run conversion with `-UseDocumentsDefault`. If they choose another folder, pass `-OutputRoot <path>` and usually `-SetDefaultOutputRoot` so future runs use it.

4. Prewarm Marker/Surya models before the first conversion, or after any failed model download:

```powershell
.\scripts\prewarm_marker_models.ps1
```

This downloads each manifest file directly into the final Datalab model cache with retry and resume support. Use it before conversion when `models.datalab.to` has intermittent SSL/network failures; it avoids Surya's temporary-directory rollback that can re-download large `.safetensors` files from scratch.

5. Convert with:

```powershell
.\scripts\convert_with_marker.ps1 -InputPath "<pdf-or-folder>" -Format html
```

Use `-PrewarmModels` on conversion when you want the conversion script to run model prewarming first.

The conversion script protects Windows paths by staging each input under a hard-truncated safe filename before calling Marker. For HTML output, it then reads the generated HTML heading/title, sanitizes and hard-truncates that paper title, and renames the output folder plus primary HTML/meta files to that title.

Use `-Format markdown`, `json`, or `chunks` only when requested. HTML is the default.

6. Verify output after conversion:

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

`install_marker.ps1` now handles the common Windows failure mode where `pip install marker-pdf` installs a CPU-only `torch` wheel despite a working NVIDIA driver. It detects `nvidia-smi` from `PATH`, `C:\Windows\System32\nvidia-smi.exe`, and the NVIDIA NVSMI directory, then installs a CUDA-enabled torch wheel unless `-SkipCudaTorch` is passed.

Use `-ForceCpu` if the user explicitly asks not to use the GPU.

## Local HTML Annotation Reader

When the user wants to review or annotate a Marker-generated HTML paper, enhance the HTML with the bundled local reader instead of modifying the original output in place.

Use:

```powershell
.\scripts\enhance_marker_html_reader.ps1 -HtmlPath "<marker-output.html>"
```

Optional:

```powershell
.\scripts\enhance_marker_html_reader.ps1 -HtmlPath "<marker-output.html>" -OutputDir "<reader-output-dir>"
```

The script copies the source HTML directory, including same-directory images and metadata, injects `assets/reader.css` and `assets/reader.js`, and returns the enhanced HTML path plus copied image count. The enhanced page supports:

- Marker heading navigation in source order, without trying to infer semantic heading levels.
- Custom annotation labels that can be added, deleted, and drag-reordered in the sidebar.
- Text annotation and caption annotation; selecting a figure/table caption is enough to annotate the associated visual.
- Page-end annotation summary.
- JSON and Markdown export for later Codex report, slide, or LaTeX generation.

## Local Sentence Translation

For lightweight local sentence translation, use Argos Translate. Do not use Ollama or other local large-language-model servers for this workflow.

Check the local translator environment first:

```powershell
.\scripts\resolve_translator.ps1 -SourceLang en -TargetLang zh
```

If the translator or language pair is missing, ask before installing because installation writes to `%LOCALAPPDATA%\Codex\tools\argos-translate\.venv` and downloads Python packages plus the Argos language package:

```powershell
.\scripts\install_translator.ps1 -SourceLang en -TargetLang zh
```

To create an annotation reader with hidden sentence translations:

```powershell
.\scripts\enhance_marker_html_reader.ps1 -HtmlPath "<marker-output.html>" -EnableTranslation
```

Use `-InstallTranslatorIfMissing` only after user approval. `-EnableTranslation` copies the source HTML directory, injects reader assets, then writes sentence-level `data-translation-id` spans plus a hidden `reader-translations` JSON script and `translations.zh.json` sidecar. The article still shows only the original text; selecting text in the reader shows the matching sentence translation beside the label chips, and saved annotations include the matched translation.

After enhancing with translation, verify that the enhanced HTML exists, `reader.css` and `reader.js` are present, `translations.<target>.json` exists, and the script reports a nonzero translation sentence count for normal English papers.

## Known Behaviors

- Marker may contact `models.datalab.to` to download or verify Surya models. If this fails because of sandbox or network restrictions, rerun with the required approval.
- If model downloads repeatedly fail after downloading large files, run `scripts/prewarm_marker_models.ps1` instead of retrying conversion. The prewarm script writes directly to the final cache and supports `curl` resume.
- CPU conversion can be slow. A 10-20 page paper may take several minutes.
- Prefer `marker_single.exe` over `marker.exe`; some installs have a batch entrypoint that fails without `psutil`.
- Marker may log "Saved markdown" even when `--output_format html` is used. Verify the actual output file extension instead of relying only on that log line.
- HTML output depends on same-directory extracted image files. Do not deliver only the `.html` file unless the user explicitly asks for a single-file derivative.
- Argos translation quality is lighter than LLM translation. It is intended for quick reading assistance, not polished publication-quality Chinese.
- Report both timings when available: the script `total_wall_seconds`/per-file `marker_wall_seconds`, and Marker's own `Total time` log line.

## Attribution

This skill is an orchestration layer for Codex. It does not vendor Marker. It uses the open source Marker/marker-pdf project by Datalab/Vik Paruchuri:

- Marker repository: https://github.com/datalab-to/marker
- Marker package: `marker-pdf`
- Marker license: GPL-3.0-or-later

When redistributing Marker itself, generated installers, or packaged environments that include Marker, preserve Marker copyright/license notices and comply with Marker license terms. For this skill repository, keep this attribution section in `SKILL.md`.

## Response Style

After conversion, give the user the primary output path, mention whether GPU or CPU was used, and note any required same-directory assets.
