"""Rezeptor documentation viewer (locale-aware markdown + GitHub link)."""

from __future__ import annotations

import html
import re
from pathlib import Path

from PyQt6.QtCore import Qt, QUrl
from PyQt6.QtGui import QDesktopServices
from PyQt6.QtWidgets import (
    QDialog,
    QHBoxLayout,
    QLabel,
    QListWidget,
    QListWidgetItem,
    QPushButton,
    QSplitter,
    QTextBrowser,
    QVBoxLayout,
    QWidget,
)

from app_support import github_doc_url
from i18n import get_locale, t

DOCS_DIR = Path(__file__).resolve().parent.parent / "docs"

# Entwickler-GUI: nur Rezept-Autoren-Doku (kein Maintainer-Handoff/GPU-Labor)
DOC_CATALOG: list[tuple[str, str, str]] = [
    ("Entwickler — Einstieg", "Developer — Getting started", "ENTWICKLER.md"),
    ("Projektstruktur", "Project layout", "PROJECT-LAYOUT.md"),
    ("Rezept erstellen (Referenz)", "Recipe authoring (reference)", "RECIPE-AUTHORING.md"),
    ("Core-API", "Core API", "CORE-API.md"),
    ("Validate & Repair", "Validate & repair", "VALIDATE-REPAIR.md"),
    ("Deinstallation", "Uninstall", "UNINSTALL.md"),
    ("Trust & Manifest", "Trust & manifest", "TRUST.md"),
    ("GUI-Launcher", "GUI launcher", "LAUNCHER.md"),
    ("Log-Protokoll", "Log protocol", "LOG-PROTOCOL.md"),
    ("Muster: Offline-Installer", "Pattern: offline installer", "INSTALLER.md"),
    ("Muster: Portable (WISO)", "Pattern: portable (WISO)", "WISO.md"),
    ("Muster: Steam + Online-Fix", "Pattern: Steam + online fix", "STEAM-WRAPPER.md"),
    ("Muster: Einzel-EXE / Trainer", "Pattern: single EXE / trainer", "TRAINER.md"),
    ("Rezept-Katalog", "Recipe catalog", "CATALOG.md"),
    ("Internationalisierung", "Internationalization", "I18N.md"),
    ("Markendesign", "Brand design", "BRAND.md"),
    ("Dokumentations-Index", "Documentation index", "README.md"),
]

def _locale_docs_dir(locale: str | None = None) -> Path:
    loc = (locale or get_locale() or "de").split("-")[0].lower()
    if loc.startswith("de"):
        loc = "de"
    else:
        loc = "en"
    preferred = DOCS_DIR / loc
    if preferred.is_dir():
        return preferred
    # Legacy flat docs/
    return DOCS_DIR


def resolve_doc_path(filename: str, locale: str | None = None) -> Path:
    base = Path(filename).name
    loc_dir = _locale_docs_dir(locale)
    candidate = loc_dir / base
    if candidate.is_file():
        return candidate
    # Fallback: other locale, then flat docs/
    for alt in ("de", "en"):
        p = DOCS_DIR / alt / base
        if p.is_file():
            return p
    flat = DOCS_DIR / base
    return flat


def load_doc_markdown(filename: str, locale: str | None = None) -> str:
    path = resolve_doc_path(filename, locale)
    if not path.is_file():
        return f"*Datei fehlt:* `{path}`"
    try:
        return path.read_text(encoding="utf-8")
    except OSError as exc:
        return f"*Lesefehler:* {exc}"


def markdown_to_html(md: str) -> str:
    """Minimal markdown → HTML for QTextBrowser (headings, code, tables, links)."""
    lines = md.splitlines()
    out: list[str] = []
    in_code = False
    code_lang = ""
    in_ul = False
    in_table = False
    table_rows: list[list[str]] = []

    def flush_ul() -> None:
        nonlocal in_ul
        if in_ul:
            out.append("</ul>")
            in_ul = False

    def flush_table() -> None:
        nonlocal in_table, table_rows
        if not table_rows:
            in_table = False
            return
        out.append('<table cellspacing="0" cellpadding="6">')
        for i, row in enumerate(table_rows):
            tag = "th" if i == 0 else "td"
            if i == 1 and all(re.match(r"^:?-+:?$", c.strip()) for c in row):
                continue
            cells = "".join(f"<{tag}>{_inline(c.strip())}</{tag}>" for c in row)
            out.append(f"<tr>{cells}</tr>")
        out.append("</table>")
        table_rows = []
        in_table = False

    def _inline(text: str) -> str:
        text = html.escape(text)
        text = re.sub(
            r"`([^`]+)`",
            r'<code style="background:#2a2a28;padding:1px 4px;border-radius:3px;">\1</code>',
            text,
        )
        text = re.sub(
            r"\*\*([^*]+)\*\*",
            r"<b>\1</b>",
            text,
        )
        text = re.sub(
            r"\[([^\]]+)\]\(([^)]+)\)",
            r'<a href="\2">\1</a>',
            text,
        )
        return text

    for line in lines:
        if line.startswith("```"):
            flush_ul()
            flush_table()
            if not in_code:
                in_code = True
                code_lang = line[3:].strip()
                out.append(
                    f'<pre style="background:#1a1a18;padding:10px;border-radius:6px;'
                    f'overflow-x:auto;"><code class="{html.escape(code_lang)}">'
                )
            else:
                in_code = False
                out.append("</code></pre>")
            continue
        if in_code:
            out.append(html.escape(line) + "\n")
            continue

        if "|" in line and line.strip().startswith("|"):
            flush_ul()
            cells = [c.strip() for c in line.strip().strip("|").split("|")]
            table_rows.append(cells)
            in_table = True
            continue
        if in_table:
            flush_table()

        if re.match(r"^#{1,3}\s+", line):
            flush_ul()
            level = len(line) - len(line.lstrip("#"))
            text = line.lstrip("#").strip()
            out.append(f"<h{level}>{_inline(text)}</h{level}>")
            continue

        if re.match(r"^[-*]\s+", line):
            if not in_ul:
                out.append("<ul>")
                in_ul = True
            out.append(f"<li>{_inline(re.sub(r'^[-*]\\s+', '', line))}</li>")
            continue
        flush_ul()

        if not line.strip():
            # Absatztrennung über CSS-Margins — kein gestapeltes <br/>
            continue
        out.append(f"<p>{_inline(line)}</p>")

    flush_ul()
    flush_table()
    if in_code:
        out.append("</code></pre>")
    return (
        '<div style="color:#EDE6D6;font-family:sans-serif;font-size:13px;line-height:1.55;">'
        "<style>"
        "p{margin:0.65em 0;} "
        "h1{margin:0.4em 0 0.7em;font-size:1.35em;} "
        "h2{margin:1.25em 0 0.55em;font-size:1.15em;} "
        "h3{margin:1em 0 0.45em;font-size:1.05em;} "
        "ul{margin:0.55em 0 0.75em 1.2em;padding:0;} "
        "li{margin:0.25em 0;} "
        "table{margin:0.85em 0;border-collapse:collapse;} "
        "th,td{border:1px solid #3a3a36;padding:6px 10px;text-align:left;} "
        "th{background:#2a2a26;} "
        "pre{margin:0.75em 0;} "
        "</style>"
        + "".join(out)
        + "</div>"
    )


class DeveloperDocsDialog(QDialog):
    """Local markdown docs with internal .md navigation and GitHub open."""

    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.setWindowTitle(t("menu.docs").rstrip("…"))
        self.resize(960, 680)
        self.setMinimumSize(640, 420)
        self._locale = get_locale()

        layout = QVBoxLayout(self)
        intro = QLabel(t("docs.intro"))
        intro.setWordWrap(True)
        intro.setObjectName("muted")
        layout.addWidget(intro)

        split = QSplitter(Qt.Orientation.Horizontal)
        self._list = QListWidget()
        self._list.setMinimumWidth(240)
        loc = (self._locale or "de").lower()
        use_en = not loc.startswith("de")
        for title_de, title_en, fname in DOC_CATALOG:
            title = title_en if use_en else title_de
            item = QListWidgetItem(title)
            item.setData(Qt.ItemDataRole.UserRole, fname)
            self._list.addItem(item)
        self._list.currentRowChanged.connect(self._on_select)
        split.addWidget(self._list)

        self._browser = QTextBrowser()
        self._browser.setObjectName("docBrowser")
        self._browser.setOpenExternalLinks(False)
        self._browser.setOpenLinks(False)
        self._browser.anchorClicked.connect(self._on_anchor)
        self._browser.setPlaceholderText("…")
        self._browser.setStyleSheet(
            "#docBrowser { background: #1C1C1A; color: #EDE6D6; padding: 8px; }"
        )
        split.addWidget(self._browser)
        split.setStretchFactor(1, 1)
        layout.addWidget(split, stretch=1)

        btn_row = QHBoxLayout()
        self._github_btn = QPushButton(t("docs.github"))
        self._github_btn.clicked.connect(self._open_github)
        btn_row.addWidget(self._github_btn)
        btn_row.addStretch(1)
        close_btn = QPushButton(t("wizard.close"))
        close_btn.clicked.connect(self.accept)
        btn_row.addWidget(close_btn)
        layout.addLayout(btn_row)

        self._current_file = ""
        if DOC_CATALOG:
            self._list.setCurrentRow(0)

    def _on_select(self, row: int) -> None:
        if row < 0:
            return
        item = self._list.item(row)
        if item is None:
            return
        fname = str(item.data(Qt.ItemDataRole.UserRole) or "")
        self._show_file(fname)

    def _show_file(self, fname: str) -> None:
        self._current_file = fname
        md = load_doc_markdown(fname, self._locale)
        self._browser.setHtml(markdown_to_html(md))
        self._github_btn.setEnabled(bool(fname))
        # Sync list selection if navigated via link
        for i in range(self._list.count()):
            it = self._list.item(i)
            if it and str(it.data(Qt.ItemDataRole.UserRole)) == fname:
                self._list.blockSignals(True)
                self._list.setCurrentRow(i)
                self._list.blockSignals(False)
                break

    def _on_anchor(self, url: QUrl) -> None:
        href = url.toString()
        if href.startswith("http://") or href.startswith("https://"):
            QDesktopServices.openUrl(url)
            return
        # Relative .md link
        path = href.split("#", 1)[0].strip()
        if path.endswith(".md") or path.endswith(".MD"):
            name = Path(path).name
            # Map legacy flat names
            self._show_file(name)
            return
        # Try as docs file without extension handling
        if path:
            QDesktopServices.openUrl(url)

    def _open_github(self) -> None:
        if not self._current_file:
            return
        loc = "de" if (self._locale or "de").lower().startswith("de") else "en"
        rel = f"{loc}/{self._current_file}"
        # Prefer locale path; fall back to flat if needed
        if not (DOCS_DIR / loc / self._current_file).is_file():
            rel = self._current_file
        url = QUrl(github_doc_url(rel))
        QDesktopServices.openUrl(url)
