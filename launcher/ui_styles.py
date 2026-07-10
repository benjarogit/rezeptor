"""QSS und Farben — einheitliches Dark-Theme für den Rezeptor-Launcher."""

from __future__ import annotations

# Status-Farben (badges, sidebar)
STATE_COLORS = {
    "not_installed": ("#6b6b6b", "#2a2a2a"),
    "partial": ("#e6a700", "#3d3200"),
    "installed": ("#3ddc84", "#0d3320"),
    "unknown": ("#888888", "#2a2a2a"),
}

APP_STYLESHEET = """
QMainWindow, QWidget {
    background-color: #1a1a1b;
    color: #e4e4e7;
    font-size: 13px;
}
QMenuBar {
    background-color: #252526;
    border-bottom: 1px solid #333337;
    padding: 2px 0;
}
QMenuBar::item:selected { background-color: #37373d; }
QMenu {
    background-color: #252526;
    border: 1px solid #333337;
}
QMenu::item:selected { background-color: #094771; }
QStatusBar {
    background-color: #252526;
    border-top: 1px solid #333337;
    color: #9d9da6;
    font-size: 11px;
    padding: 0 8px;
}
QLabel#statusFooter {
    color: #9d9da6;
    padding: 0 4px;
}
QFrame#sidebar {
    background-color: #252526;
    border-right: 1px solid #333337;
}
QFrame#headerCard {
    background-color: #2d2d30;
    border: 1px solid #3e3e42;
    border-radius: 8px;
}
QFrame#actionBar {
    background-color: transparent;
    border: none;
}
QFrame#contentShell {
    background-color: #2d2d30;
    border: 1px solid #3e3e42;
    border-radius: 8px;
}
QStackedWidget {
    background-color: transparent;
}
QLabel#sidebarTitle {
    color: #9d9da6;
    font-size: 11px;
    font-weight: 600;
    letter-spacing: 0.06em;
}
QLabel#appTitle {
    font-size: 20px;
    font-weight: 600;
}
QLabel#appPath {
    color: #9d9da6;
    font-size: 11px;
}
QLabel#statusChip {
    border-radius: 10px;
    padding: 3px 10px;
    font-size: 11px;
    font-weight: 600;
}
QLabel#stepLabel {
    font-weight: 600;
    color: #cccccc;
}
QLabel#muted { color: #a1a1aa; font-size: 12px; }
QListWidget#activityList {
    background-color: #18181b;
    border: 1px solid #3f3f46;
    border-radius: 6px;
    font-family: "JetBrains Mono", "Fira Code", monospace;
    font-size: 12px;
}
QListWidget#activityList::item { padding: 4px 8px; border: none; }
QTextBrowser#infoBrowser {
    background-color: transparent;
    border: none;
    padding: 4px 0;
}
QListWidget {
    background-color: transparent;
    border: none;
    outline: none;
}
QListWidget::item {
    border-radius: 6px;
    padding: 10px 8px;
    margin: 2px 4px;
}
QListWidget::item:selected {
    background-color: #094771;
}
QListWidget::item:hover:!selected {
    background-color: #2a2d2e;
}
QGroupBox {
    font-weight: 600;
    border: 1px solid #3e3e42;
    border-radius: 6px;
    margin-top: 10px;
    padding-top: 8px;
}
QGroupBox::title {
    subcontrol-origin: margin;
    left: 10px;
    padding: 0 4px;
    color: #9d9da6;
}
QTabWidget::pane {
    border: 1px solid #3e3e42;
    border-radius: 6px;
    background-color: #1e1e1e;
    top: -1px;
}
QTabBar::tab {
    background-color: #2d2d30;
    border: 1px solid #3e3e42;
    border-bottom: none;
    border-top-left-radius: 4px;
    border-top-right-radius: 4px;
    padding: 6px 14px;
    margin-right: 2px;
    color: #9d9da6;
}
QTabBar::tab:selected {
    background-color: #1e1e1e;
    color: #e4e4e7;
    border-bottom: 1px solid #1e1e1e;
}
QTextEdit, QTextBrowser, QComboBox {
    background-color: #1e1e1e;
    border: 1px solid #3e3e42;
    border-radius: 4px;
    selection-background-color: #094771;
}
QProgressBar {
    border: 1px solid #3e3e42;
    border-radius: 4px;
    background-color: #2d2d30;
    text-align: center;
    height: 18px;
}
QProgressBar::chunk {
    background-color: #0e639c;
    border-radius: 3px;
}
QPushButton {
    background-color: #3e3e42;
    border: 1px solid #4e4e52;
    border-radius: 4px;
    padding: 7px 14px;
    min-height: 18px;
}
QPushButton:hover { background-color: #4e4e52; }
QPushButton:pressed { background-color: #2d2d30; }
QPushButton:disabled {
    background-color: #2a2a2b;
    color: #6b6b6b;
    border-color: #333337;
}
QPushButton#primaryBtn {
    background-color: #0e639c;
    border-color: #1177bb;
    color: #ffffff;
    font-weight: 600;
    padding: 8px 22px;
}
QPushButton#primaryBtn:hover { background-color: #1177bb; }
QPushButton#primaryBtn:disabled {
    background-color: #1a3a4f;
    color: #6b8fa8;
    border-color: #1a3a4f;
}
QPushButton#ghostBtn {
    background-color: transparent;
    border-color: #4e4e52;
}
QToolButton {
    background-color: #3e3e42;
    border: 1px solid #4e4e52;
    border-radius: 4px;
    padding: 6px 12px;
}
QToolButton:hover { background-color: #4e4e52; }
QToolButton::menu-indicator { image: none; width: 0; }
QSplitter::handle { background-color: #333337; width: 1px; }
"""
