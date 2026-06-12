(function () {
  const DEFAULT_LABELS = [
    { id: "problem", name: "\u95ee\u9898", color: "#ffe0df" },
    { id: "method", name: "\u65b9\u6cd5", color: "#fff2a8" },
    { id: "experiment", name: "\u5b9e\u9a8c", color: "#d8f3f0" },
    { id: "result", name: "\u7ed3\u679c", color: "#ffe7bd" },
    { id: "question", name: "\u7591\u95ee", color: "#eadcff" }
  ];

  const LABEL_COLORS = [
    "#fff2a8",
    "#d9ecff",
    "#dff7e5",
    "#ffe0df",
    "#efe3ff",
    "#d8f3f0",
    "#ffe7bd",
    "#ffd7e2",
    "#e5f4cf",
    "#e7f0ff"
  ];

  const BLOCK_SELECTOR = "p, li, th, td, h1, h2, h3, h4, h5, h6";
  const HEADING_SELECTOR = "h1, h2, h3, h4, h5, h6";
  const STORAGE_KEY = "paper-reader:" + location.pathname;
  const state = loadState();
  const paperTitle = textOf(document.querySelector("h1")) || document.title || "paper";

  let labels = normalizeLabels(state.labels);
  let annotations = migrateAnnotations(state.annotations || []);
  let translations = loadTranslations();
  let completed = Boolean(state.completed);
  let activeRange = null;
  let activeBlock = null;
  let blockCounter = 0;

  document.addEventListener("DOMContentLoaded", init);

  function init() {
    assignBlocks();
    buildShell();
    restoreMarks();
    renderLabelList();
    renderSelectionMenu();
    renderSummary();
    bindSelection();
    document.body.classList.add("reader-ready");
  }

  function assignBlocks() {
    document.querySelectorAll(BLOCK_SELECTOR).forEach((block) => {
      if (!block.dataset.readerBlock) {
        block.dataset.readerBlock = "block-" + (++blockCounter);
      }
    });
  }

  function buildShell() {
    const bodyNodes = Array.from(document.body.childNodes);
    const shell = el("div", "reader-shell");
    const sidebar = el("aside", "reader-sidebar");
    const navArea = el("section", "reader-sidebar-section reader-nav-section");
    const labelArea = buildLabelManager();
    const main = el("main", "reader-main");
    const topbar = el("div", "reader-topbar");
    const status = el("div", "reader-status");
    status.id = "reader-status";
    const actions = el("div", "reader-actions");
    const article = el("article", "reader-article");
    article.id = "reader-article";
    const summary = el("section", "reader-summary");
    summary.id = "annotation-summary";

    actions.append(
      button("\u5bfc\u51fa JSON", "", exportJson),
      button("\u5bfc\u51fa Markdown", "", exportMarkdown),
      button("\u6807\u6ce8\u5b8c\u6210", "primary", markCompleted)
    );
    topbar.append(status, actions);

    bodyNodes.forEach((node) => {
      if (node.nodeType === Node.ELEMENT_NODE) {
        const tag = node.tagName.toLowerCase();
        if (tag === "script" || tag === "link" || tag === "style") return;
      }
      article.append(node);
    });

    navArea.append(el("h2", "", "\u7ae0\u8282"));
    navArea.append(buildNav(article));
    sidebar.append(navArea, labelArea);

    main.append(topbar, article, summary);
    shell.append(sidebar, main);
    document.body.append(shell, buildSelectionMenu(), el("div", "reader-toast"));
    updateStatus();
  }

  function buildNav(article) {
    const nav = el("nav", "reader-nav");
    const headings = Array.from(article.querySelectorAll(HEADING_SELECTOR));
    headings.forEach((heading, index) => {
      if (!heading.id) heading.id = "reader-heading-" + index;
      const link = el("a", "marker-heading", compact(textOf(heading), 86));
      link.href = "#" + heading.id;
      link.title = normalize(textOf(heading));
      link.dataset.headingTag = heading.tagName.toLowerCase();
      link.addEventListener("click", () => {
        setTimeout(() => setActiveNav(link), 0);
      });
      nav.append(link);
    });

    if (!headings.length) {
      nav.append(el("div", "reader-summary-empty", "\u6ca1\u6709\u8bc6\u522b\u5230\u6807\u9898"));
      return nav;
    }

    const observer = new IntersectionObserver((entries) => {
      const visible = entries
        .filter((entry) => entry.isIntersecting)
        .sort((a, b) => b.intersectionRatio - a.intersectionRatio)[0];
      if (!visible) return;
      const link = nav.querySelector('a[href="#' + CSS.escape(visible.target.id) + '"]');
      if (link) setActiveNav(link);
    }, { rootMargin: "-12% 0px -75% 0px", threshold: [0, 0.2, 1] });

    headings.forEach((heading) => observer.observe(heading));
    return nav;
  }

  function buildLabelManager() {
    const panel = el("section", "reader-sidebar-section reader-label-panel");
    const title = el("h2", "", "\u6807\u7b7e");
    const form = el("div", "reader-label-form");
    const input = document.createElement("input");
    input.id = "reader-label-input";
    input.type = "text";
    input.placeholder = "\u65b0\u589e\u6807\u7b7e";
    input.addEventListener("keydown", (event) => {
      if (event.key === "Enter") {
        event.preventDefault();
        addLabelFromInput();
      }
    });
    form.append(input, button("\u6dfb\u52a0", "", addLabelFromInput));
    panel.append(title, form, el("div", "reader-label-list"));
    return panel;
  }

  function buildSelectionMenu() {
    const menu = el("div", "reader-selection-menu");
    menu.id = "reader-selection-menu";
    menu.append(el("div", "reader-menu-title", "\u9009\u62e9\u6807\u6ce8\u6807\u7b7e"));
    menu.append(el("div", "reader-chip-row"));
    menu.append(el("div", "reader-translation-panel"));
    return menu;
  }

  function renderSelectionMenu() {
    const row = document.querySelector("#reader-selection-menu .reader-chip-row");
    if (!row) return;
    row.innerHTML = "";
    labels.forEach((label) => {
      const chip = button(label.name, "reader-chip", () => addAnnotation(label.id));
      chip.dataset.labelId = label.id;
      chip.style.backgroundColor = label.color;
      row.append(chip);
    });
    if (!labels.length) {
      row.append(el("div", "reader-summary-empty", "\u5148\u6dfb\u52a0\u4e00\u4e2a\u6807\u7b7e"));
    }
  }

  function renderSelectionTranslation(range, block) {
    const panel = document.querySelector(".reader-translation-panel");
    if (!panel) return;
    panel.innerHTML = "";
    if (!range || !block) return;

    const matches = translationForRange(range, block);
    if (!matches.length) {
      if (hasTranslations()) {
        panel.append(el("div", "reader-translation-empty", "\u672a\u5339\u914d\u5230\u8be5\u9009\u533a\u7684\u53e5\u5b50\u8bd1\u6587"));
      }
      return;
    }

    panel.append(el("div", "reader-translation-title", "\u53e5\u5b50\u8bd1\u6587"));
    matches.slice(0, 3).forEach((item) => {
      const card = el("div", "reader-translation-card");
      card.append(el("div", "reader-translation-source", item.source));
      card.append(el("div", "reader-translation-text", item.translation));
      panel.append(card);
    });
  }

  function translationForRange(range, block) {
    if (!range || !block || !hasTranslations()) return [];
    const items = [];
    const seen = new Set();
    block.querySelectorAll("[data-translation-id]").forEach((span) => {
      if (!rangeIntersects(range, span)) return;
      const id = span.dataset.translationId;
      const item = translations[id];
      if (!item || seen.has(id)) return;
      seen.add(id);
      items.push(item);
    });

    if (items.length) return items;

    const selectedText = normalize(range.toString()).toLowerCase();
    if (!selectedText || selectedText.length < 8) return [];
    block.querySelectorAll("[data-translation-id]").forEach((span) => {
      if (items.length >= 2) return;
      const id = span.dataset.translationId;
      const item = translations[id];
      if (!item || seen.has(id)) return;
      const source = normalize(item.source).toLowerCase();
      if (source.includes(selectedText) || selectedText.includes(source)) {
        seen.add(id);
        items.push(item);
      }
    });
    return items;
  }

  function rangeIntersects(range, node) {
    try {
      return range.intersectsNode(node);
    } catch (error) {
      return false;
    }
  }

  function hasTranslations() {
    return translations && Object.keys(translations).length > 0;
  }

  function renderLabelList() {
    const list = document.querySelector(".reader-label-list");
    if (!list) return;
    list.innerHTML = "";
    labels.forEach((label, index) => {
      const item = el("div", "reader-label-item");
      const swatch = el("span", "reader-label-swatch");
      swatch.style.backgroundColor = label.color;
      const name = el("span", "reader-label-name", label.name);
      const actions = el("span", "reader-label-actions");
      actions.append(
        smallButton("\u2191", "\u4e0a\u79fb", () => moveLabel(index, -1), index === 0),
        smallButton("\u2193", "\u4e0b\u79fb", () => moveLabel(index, 1), index === labels.length - 1),
        smallButton("\u00d7", "\u5220\u9664", () => deleteLabel(label.id), false)
      );
      item.append(swatch, name, actions);
      list.append(item);
    });
  }

  function bindSelection() {
    document.addEventListener("selectionchange", () => {
      const selection = window.getSelection();
      const menu = document.getElementById("reader-selection-menu");
      if (!selection || selection.rangeCount === 0 || selection.isCollapsed) {
        menu.classList.remove("open");
        renderSelectionTranslation(null, null);
        return;
      }

      const range = selection.getRangeAt(0);
      const article = document.getElementById("reader-article");
      if (!article.contains(range.commonAncestorContainer)) {
        menu.classList.remove("open");
        return;
      }

      const block = closestBlock(range.commonAncestorContainer);
      if (!block) {
        menu.classList.remove("open");
        return;
      }

      activeRange = range.cloneRange();
      activeBlock = block;
      const rect = range.getBoundingClientRect();
      menu.style.left = clamp(rect.left, 14, window.innerWidth - 574) + "px";
      menu.style.top = clamp(rect.bottom + 8, 14, window.innerHeight - 128) + "px";
      renderSelectionTranslation(activeRange, activeBlock);
      menu.classList.add("open");
    });

    document.addEventListener("mousedown", (event) => {
      const menu = document.getElementById("reader-selection-menu");
      if (!menu.contains(event.target)) return;
      event.preventDefault();
    });
  }

  function addAnnotation(labelId) {
    if (!activeRange || !activeBlock) return;
    const label = labelById(labelId);
    if (!label) {
      toast("\u8bf7\u5148\u9009\u62e9\u6709\u6548\u6807\u7b7e\u3002");
      return;
    }

    const selectedText = normalize(activeRange.toString());
    if (!selectedText) return;

    const article = document.getElementById("reader-article");
    const commonBlock = closestBlock(activeRange.commonAncestorContainer);
    if (!commonBlock || !article.contains(commonBlock)) {
      toast("\u8bf7\u5728\u6b63\u6587\u3001\u6807\u9898\u6216\u9898\u6ce8\u5185\u9009\u62e9\u6587\u672c\u3002");
      return;
    }

    const caption = detectCaption(commonBlock, selectedText);
    const matchedTranslations = translationForRange(activeRange, commonBlock);
    const id = "ann-" + Date.now().toString(36) + "-" + Math.random().toString(36).slice(2, 7);
    const section = currentSection(commonBlock);
    const markOk = wrapRange(activeRange, id, labelId);

    annotations.push({
      id,
      labelId,
      label: label.name,
      text: selectedText,
      translation: matchedTranslations.map((item) => item.translation).filter(Boolean).join("\n"),
      note: "",
      section,
      blockId: commonBlock.dataset.readerBlock,
      blockText: normalize(textOf(commonBlock)).slice(0, 420),
      isCaption: caption.isCaption,
      mediaSrc: caption.mediaSrc,
      order: annotations.length + 1,
      createdAt: new Date().toISOString()
    });

    completed = false;
    saveState();
    renderSummary();
    updateStatus();
    window.getSelection().removeAllRanges();
    document.getElementById("reader-selection-menu").classList.remove("open");
    toast(markOk ? "\u5df2\u6dfb\u52a0\u6807\u6ce8\u3002" : "\u5df2\u8bb0\u5f55\u6807\u6ce8\uff0c\u4f46\u8fd9\u6bb5\u9009\u62e9\u65e0\u6cd5\u5b89\u5168\u7740\u8272\u3002");
  }

  function wrapRange(range, id, labelId) {
    try {
      const mark = document.createElement("mark");
      mark.className = "reader-mark";
      mark.dataset.annotationId = id;
      mark.dataset.labelId = labelId;
      mark.style.backgroundColor = colorForLabel(labelId);
      mark.append(range.extractContents());
      range.insertNode(mark);
      return true;
    } catch (error) {
      return false;
    }
  }

  function restoreMarks() {
    annotations.forEach((annotation) => {
      const labelId = annotation.labelId || annotation.type;
      if (document.querySelector('[data-annotation-id="' + CSS.escape(annotation.id) + '"]')) return;
      const block = document.querySelector('[data-reader-block="' + CSS.escape(annotation.blockId || "") + '"]');
      if (block) markTextInBlock(block, annotation.text, annotation.id, labelId);
    });
  }

  function markTextInBlock(block, text, id, labelId) {
    const walker = document.createTreeWalker(block, NodeFilter.SHOW_TEXT, {
      acceptNode(node) {
        if (!normalize(node.nodeValue).includes(normalize(text))) return NodeFilter.FILTER_REJECT;
        if (node.parentElement && node.parentElement.closest(".reader-mark")) return NodeFilter.FILTER_REJECT;
        return NodeFilter.FILTER_ACCEPT;
      }
    });
    const node = walker.nextNode();
    if (!node) return false;
    const index = node.nodeValue.indexOf(text);
    if (index < 0) return false;
    const range = document.createRange();
    range.setStart(node, index);
    range.setEnd(node, index + text.length);
    return wrapRange(range, id, labelId);
  }

  function renderSummary() {
    const summary = document.getElementById("annotation-summary");
    if (!summary) return;
    summary.innerHTML = "";
    summary.append(el("h2", "", "\u6807\u6ce8\u6c47\u603b"));
    summary.append(el("div", "reader-status", completed ? "\u72b6\u6001\uff1a\u5df2\u6807\u6ce8\u5b8c\u6210" : "\u72b6\u6001\uff1a\u7ee7\u7eed\u6807\u6ce8\u4e2d"));

    if (!annotations.length) {
      summary.append(el("p", "reader-summary-empty", "\u8fd8\u6ca1\u6709\u6807\u6ce8\u3002\u9009\u4e2d\u6b63\u6587\u6216\u56fe\u7247\u9898\u6ce8\u540e\uff0c\u9009\u62e9\u4e00\u4e2a\u6807\u7b7e\u5373\u53ef\u6dfb\u52a0\u3002"));
      return;
    }

    orderedLabelIds().forEach((labelId) => {
      const items = annotations.filter((annotation) => annotationLabelId(annotation) === labelId);
      if (!items.length) return;
      const label = labelById(labelId) || { id: labelId, name: items[0].label || labelId };
      const group = el("div", "reader-summary-group");
      group.append(el("h3", "", label.name + " (" + items.length + ")"));
      items.forEach((annotation) => group.append(annotationCard(annotation)));
      summary.append(group);
    });
  }

  function annotationCard(annotation) {
    const card = el("article", "reader-card");
    const meta = el("div", "reader-card-meta");
    meta.append(
      el("span", "", "#" + annotation.order),
      el("span", "", annotation.section || "\u672a\u8bc6\u522b\u7ae0\u8282")
    );
    if (annotation.isCaption) meta.append(el("span", "", "\u9898\u6ce8"));
    if (annotation.mediaSrc) meta.append(el("span", "", annotation.mediaSrc));

    const text = el("p", "reader-card-text", annotation.text);
    const translation = annotation.translation ? el("p", "reader-card-translation", annotation.translation) : null;
    const note = document.createElement("textarea");
    note.placeholder = "\u5907\u6ce8\uff0c\u53ef\u9009";
    note.value = annotation.note || "";
    note.addEventListener("input", () => {
      annotation.note = note.value;
      saveState();
    });

    const actions = el("div", "reader-card-actions");
    actions.append(
      button("\u5b9a\u4f4d", "", () => jumpToAnnotation(annotation)),
      button("\u5220\u9664", "", () => removeAnnotation(annotation.id))
    );

    card.append(meta, text);
    if (translation) card.append(translation);
    card.append(note, actions);
    return card;
  }

  function jumpToAnnotation(annotation) {
    const mark = document.querySelector('[data-annotation-id="' + CSS.escape(annotation.id) + '"]');
    const block = document.querySelector('[data-reader-block="' + CSS.escape(annotation.blockId || "") + '"]');
    const target = mark || block;
    if (!target) {
      toast("\u6ca1\u6709\u627e\u5230\u539f\u6587\u4f4d\u7f6e\u3002");
      return;
    }
    target.scrollIntoView({ behavior: "smooth", block: "center" });
    if (mark) {
      mark.animate([
        { outline: "2px solid #2166d5" },
        { outline: "2px solid transparent" }
      ], { duration: 1300 });
    }
  }

  function removeAnnotation(id) {
    annotations = annotations.filter((annotation) => annotation.id !== id);
    const mark = document.querySelector('[data-annotation-id="' + CSS.escape(id) + '"]');
    if (mark) mark.replaceWith(...Array.from(mark.childNodes));
    completed = false;
    saveState();
    renderSummary();
    updateStatus();
  }

  function addLabelFromInput() {
    const input = document.getElementById("reader-label-input");
    const name = normalize(input && input.value);
    if (!name) return;
    labels.push({
      id: "label-" + Date.now().toString(36) + "-" + Math.random().toString(36).slice(2, 6),
      name,
      color: LABEL_COLORS[labels.length % LABEL_COLORS.length]
    });
    input.value = "";
    saveState();
    renderLabelList();
    renderSelectionMenu();
    renderSummary();
  }

  function moveLabel(index, direction) {
    const next = index + direction;
    if (next < 0 || next >= labels.length) return;
    const copy = labels.slice();
    const temp = copy[index];
    copy[index] = copy[next];
    copy[next] = temp;
    labels = copy;
    saveState();
    renderLabelList();
    renderSelectionMenu();
    renderSummary();
  }

  function deleteLabel(labelId) {
    labels = labels.filter((label) => label.id !== labelId);
    saveState();
    renderLabelList();
    renderSelectionMenu();
    renderSummary();
  }

  function markCompleted() {
    completed = true;
    saveState();
    renderSummary();
    updateStatus();
    exportJson();
    toast("\u5df2\u6807\u8bb0\u5b8c\u6210\uff0c\u5e76\u5bfc\u51fa JSON\u3002");
  }

  function exportJson() {
    const payload = {
      paperTitle,
      sourceHtml: location.pathname.split("/").pop(),
      completed,
      completedAt: completed ? new Date().toISOString() : null,
      labels,
      annotationCount: annotations.length,
      annotations
    };
    download(slug(paperTitle) + "_annotations.json", JSON.stringify(payload, null, 2), "application/json");
  }

  function exportMarkdown() {
    const lines = ["# " + paperTitle, "", "## Annotation Summary", ""];
    orderedLabelIds().forEach((labelId) => {
      const items = annotations.filter((annotation) => annotationLabelId(annotation) === labelId);
      if (!items.length) return;
      const label = labelById(labelId) || { name: items[0].label || labelId };
      lines.push("### " + label.name, "");
      items.forEach((annotation) => {
        lines.push("- Section: " + (annotation.section || "Unknown"));
        if (annotation.isCaption) lines.push("  Type: caption");
        if (annotation.mediaSrc) lines.push("  Media: " + annotation.mediaSrc);
        lines.push("  Text: " + annotation.text.replace(/\s+/g, " "));
        if (annotation.translation) lines.push("  Translation: " + annotation.translation.replace(/\s+/g, " "));
        if (annotation.note) lines.push("  Note: " + annotation.note.replace(/\s+/g, " "));
        lines.push("");
      });
    });
    download(slug(paperTitle) + "_annotations.md", lines.join("\n"), "text/markdown");
  }

  function detectCaption(block, selectedText) {
    const blockText = normalize(textOf(block));
    const looksLikeCaption = /^(fig\.|figure|table|TABLE|Fig\.)\s*\d*/.test(blockText) || /^(fig\.|figure|table|TABLE|Fig\.)\s*\d*/.test(selectedText);
    let mediaSrc = "";
    const previous = previousElement(block);
    const img = previous && previous.querySelector ? previous.querySelector("img") : null;
    if (img) mediaSrc = img.getAttribute("src") || "";
    return { isCaption: looksLikeCaption, mediaSrc };
  }

  function currentSection(block) {
    let node = block;
    while (node && node !== document.body) {
      let cursor = node.previousElementSibling;
      while (cursor) {
        if (/^H[1-6]$/.test(cursor.tagName)) return compact(textOf(cursor), 120);
        cursor = cursor.previousElementSibling;
      }
      node = node.parentElement;
    }
    return compact(textOf(document.querySelector(".reader-article h1")), 120);
  }

  function closestBlock(node) {
    const element = node.nodeType === Node.ELEMENT_NODE ? node : node.parentElement;
    return element ? element.closest(BLOCK_SELECTOR) : null;
  }

  function previousElement(element) {
    let node = element.previousElementSibling;
    while (node && !textOf(node) && !node.querySelector("img")) node = node.previousElementSibling;
    return node;
  }

  function normalizeLabels(rawLabels) {
    const source = Array.isArray(rawLabels) && rawLabels.length ? rawLabels : DEFAULT_LABELS;
    const seen = new Set();
    return source
      .map((label, index) => ({
        id: String(label.id || "label-" + index),
        name: normalize(label.name || label.label || label.id || ("Label " + (index + 1))),
        color: label.color || LABEL_COLORS[index % LABEL_COLORS.length]
      }))
      .filter((label) => {
        if (!label.name || seen.has(label.id)) return false;
        seen.add(label.id);
        return true;
      });
  }

  function migrateAnnotations(rawAnnotations) {
    return rawAnnotations.map((annotation, index) => {
      const labelId = annotation.labelId || annotation.type || "method";
      const label = labelById(labelId);
      return {
        ...annotation,
        labelId,
        label: annotation.label || (label ? label.name : labelId),
        order: annotation.order || index + 1
      };
    });
  }

  function orderedLabelIds() {
    const ids = labels.map((label) => label.id);
    annotations.forEach((annotation) => {
      const labelId = annotationLabelId(annotation);
      if (!ids.includes(labelId)) ids.push(labelId);
    });
    return ids;
  }

  function annotationLabelId(annotation) {
    return annotation.labelId || annotation.type || "method";
  }

  function labelById(id) {
    return labels.find((label) => label.id === id);
  }

  function colorForLabel(id) {
    const label = labelById(id);
    return label ? label.color : "#fff2a8";
  }

  function loadState() {
    try {
      return JSON.parse(localStorage.getItem(STORAGE_KEY) || "{}");
    } catch (error) {
      return {};
    }
  }

  function loadTranslations() {
    const script = document.getElementById("reader-translations");
    if (!script) return {};
    try {
      const payload = JSON.parse(script.textContent || "{}");
      return payload.items || {};
    } catch (error) {
      return {};
    }
  }

  function saveState() {
    localStorage.setItem(STORAGE_KEY, JSON.stringify({ completed, labels, annotations }));
  }

  function updateStatus() {
    const status = document.getElementById("reader-status");
    if (!status) return;
    status.textContent = annotations.length + " \u6761\u6807\u6ce8" + (completed ? "\uff0c\u5df2\u5b8c\u6210" : "\uff0c\u672a\u5b8c\u6210");
  }

  function setActiveNav(link) {
    document.querySelectorAll(".reader-nav a").forEach((item) => item.classList.remove("active"));
    link.classList.add("active");
  }

  function button(label, className, onClick) {
    const btn = document.createElement("button");
    btn.type = "button";
    btn.className = className && className.includes("reader-chip") ? className : "reader-button" + (className ? " " + className : "");
    btn.textContent = label;
    btn.addEventListener("click", onClick);
    return btn;
  }

  function smallButton(label, title, onClick, disabled) {
    const btn = button(label, "reader-small-button", onClick);
    btn.title = title;
    btn.disabled = disabled;
    return btn;
  }

  function el(tag, className, text) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined) node.textContent = text;
    return node;
  }

  function textOf(node) {
    return node ? node.textContent || "" : "";
  }

  function normalize(value) {
    return (value || "").replace(/\s+/g, " ").trim();
  }

  function compact(value, limit) {
    const text = normalize(value);
    return text.length > limit ? text.slice(0, limit - 1) + "..." : text;
  }

  function clamp(value, min, max) {
    return Math.max(min, Math.min(value, max));
  }

  function slug(value) {
    return normalize(value).toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, "").slice(0, 80) || "paper";
  }

  function download(filename, content, type) {
    const blob = new Blob([content], { type });
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    link.download = filename;
    document.body.append(link);
    link.click();
    link.remove();
    URL.revokeObjectURL(url);
  }

  function toast(message) {
    const node = document.querySelector(".reader-toast");
    node.textContent = message;
    node.classList.add("show");
    clearTimeout(toast.timer);
    toast.timer = setTimeout(() => node.classList.remove("show"), 2200);
  }
})();
