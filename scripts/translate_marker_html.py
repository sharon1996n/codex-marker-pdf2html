import argparse
import json
import re
from pathlib import Path

from bs4 import BeautifulSoup, NavigableString
from argostranslate import translate


BLOCK_TAGS = {"p", "li", "th", "td", "h1", "h2", "h3", "h4", "h5", "h6"}
SKIP_TAGS = {"script", "style", "code", "pre", "math", "svg"}
SENTENCE_RE = re.compile(r"(.+?(?:[.!?](?=\s+[\[(\"'A-Z0-9])|[.!?]$)))(\s*)", re.S)


def normalize(text: str) -> str:
    return re.sub(r"\s+", " ", text or "").strip()


def split_sentences(text: str):
    if not normalize(text):
        return [(text, False)]

    parts = []
    pos = 0
    for match in SENTENCE_RE.finditer(text):
        if match.start() > pos:
            parts.append((text[pos:match.start()], False))
        sentence = match.group(1)
        space = match.group(2) or ""
        parts.append((sentence, True))
        if space:
            parts.append((space, False))
        pos = match.end()
    if pos < len(text):
        tail = text[pos:]
        parts.append((tail, len(normalize(tail)) >= 24))
    return parts


def should_translate(text: str) -> bool:
    compact = normalize(text)
    if len(compact) < 24:
        return False
    letters = sum(ch.isalpha() for ch in compact)
    return letters >= max(8, len(compact) * 0.45)


def get_translation(source_lang: str, target_lang: str):
    installed = translate.get_installed_languages()
    from_lang = next((lang for lang in installed if lang.code == source_lang), None)
    to_lang = next((lang for lang in installed if lang.code == target_lang), None)
    if not from_lang or not to_lang:
        raise RuntimeError(f"Argos languages are not installed: {source_lang}->{target_lang}")
    translation = from_lang.get_translation(to_lang)
    if translation is None:
        raise RuntimeError(f"Argos language pair is not installed: {source_lang}->{target_lang}")
    return translation


def ancestor_tags(node):
    parent = node.parent
    while parent is not None:
        if getattr(parent, "name", None):
            yield parent.name.lower(), parent
        parent = parent.parent


def text_node_is_eligible(node):
    for tag_name, _parent in ancestor_tags(node):
        if tag_name in SKIP_TAGS:
            return False
        if tag_name in BLOCK_TAGS:
            return True
    return False


def remove_old_translation_data(soup):
    old_data = soup.find("script", id="reader-translations")
    if old_data:
        old_data.decompose()
    for span in soup.select("[data-translation-id]"):
        span.unwrap()


def translate_html(input_path: Path, output_path: Path, source_lang: str, target_lang: str):
    soup = BeautifulSoup(input_path.read_text(encoding="utf-8"), "html.parser")
    remove_old_translation_data(soup)
    translator = get_translation(source_lang, target_lang)

    translations = {}
    cache = {}
    counter = 0

    for node in list(soup.find_all(string=True)):
        if not isinstance(node, NavigableString):
            continue
        if not text_node_is_eligible(node):
            continue
        parts = split_sentences(str(node))
        if not any(is_sentence and should_translate(text) for text, is_sentence in parts):
            continue

        replacement = []
        for text, is_sentence in parts:
            source = normalize(text)
            if not is_sentence or not should_translate(source):
                replacement.append(NavigableString(text))
                continue

            counter += 1
            sentence_id = f"tr-{counter:06d}"
            if source not in cache:
                cache[source] = normalize(translator.translate(source))
            span = soup.new_tag("span")
            span["data-translation-id"] = sentence_id
            span["class"] = "reader-sentence"
            span.string = text
            replacement.append(span)
            translations[sentence_id] = {
                "source": source,
                "translation": cache[source],
            }

        node.replace_with(*replacement)

    payload = {
        "version": 1,
        "source_lang": source_lang,
        "target_lang": target_lang,
        "engine": "argos-translate",
        "count": len(translations),
        "items": translations,
    }

    data_script = soup.new_tag("script", id="reader-translations", type="application/json")
    data_script.string = json.dumps(payload, ensure_ascii=False)
    if soup.body:
        soup.body.append(data_script)
    else:
        soup.append(data_script)

    output_path.write_text(str(soup), encoding="utf-8")
    sidecar = output_path.with_name(f"translations.{target_lang}.json")
    sidecar.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    return payload, sidecar


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--html", required=True)
    parser.add_argument("--output-html")
    parser.add_argument("--source-lang", default="en")
    parser.add_argument("--target-lang", default="zh")
    args = parser.parse_args()

    input_path = Path(args.html)
    output_path = Path(args.output_html) if args.output_html else input_path.with_name(input_path.stem + f".{args.target_lang}.html")
    payload, sidecar = translate_html(input_path, output_path, args.source_lang, args.target_lang)
    print(json.dumps({
        "status": "translated",
        "html": str(output_path),
        "translation_json": str(sidecar),
        "source_lang": args.source_lang,
        "target_lang": args.target_lang,
        "sentence_count": payload["count"],
        "engine": payload["engine"],
    }, ensure_ascii=True))


if __name__ == "__main__":
    main()
