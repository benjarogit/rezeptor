"""Dialog: Rezepte aus Katalog / GitHub hinzufügen (+ optionale Fremdquelle)."""

from __future__ import annotations

from pathlib import Path

from PyQt6.QtCore import Qt
from PyQt6.QtWidgets import (
    QDialog,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QListWidget,
    QListWidgetItem,
    QMessageBox,
    QPushButton,
    QVBoxLayout,
    QWidget,
)

from i18n import t
from recipe_catalog import (
    DEFAULT_GITHUB_REPO,
    CatalogEntry,
    CatalogError,
    RecipeInstallError,
    fetch_catalog_from_github,
    install_recipe_from_github,
    load_local_catalog,
)
from settings import RezeptorSettings, save_settings


class CatalogDialog(QDialog):
    def __init__(
        self,
        parent: QWidget | None,
        *,
        recipes_dir: Path,
        settings: RezeptorSettings,
        installed_ids: set[str],
    ) -> None:
        super().__init__(parent)
        self._recipes_dir = recipes_dir
        self._settings = settings
        self._installed = set(installed_ids)
        self._entries: list[CatalogEntry] = []
        self.setWindowTitle(t("catalog.title"))
        self.resize(560, 480)

        root = QVBoxLayout(self)
        intro = QLabel(t("catalog.intro"))
        intro.setWordWrap(True)
        intro.setObjectName("muted")
        root.addWidget(intro)

        warn = QLabel(t("catalog.foreign_warn"))
        warn.setWordWrap(True)
        warn.setObjectName("muted")
        root.addWidget(warn)

        src_row = QHBoxLayout()
        self.source_edit = QLineEdit()
        self.source_edit.setPlaceholderText(t("catalog.source_ph"))
        self.source_edit.setText(DEFAULT_GITHUB_REPO)
        src_row.addWidget(self.source_edit, stretch=1)
        refresh_btn = QPushButton(t("catalog.refresh"))
        refresh_btn.clicked.connect(self._reload)
        src_row.addWidget(refresh_btn)
        root.addLayout(src_row)

        self.list = QListWidget()
        self.list.itemDoubleClicked.connect(lambda _i: self._install_selected())
        root.addWidget(self.list, stretch=1)

        self.status = QLabel("")
        self.status.setObjectName("muted")
        root.addWidget(self.status)

        btn_row = QHBoxLayout()
        add_src = QPushButton(t("catalog.add_source"))
        add_src.clicked.connect(self._remember_source)
        btn_row.addWidget(add_src)
        btn_row.addStretch(1)
        install_btn = QPushButton(t("catalog.install"))
        install_btn.clicked.connect(self._install_selected)
        btn_row.addWidget(install_btn)
        close_btn = QPushButton(t("catalog.close"))
        close_btn.clicked.connect(self.accept)
        btn_row.addWidget(close_btn)
        root.addLayout(btn_row)

        self._reload()

    def _repo(self) -> str:
        return (self.source_edit.text() or DEFAULT_GITHUB_REPO).strip()

    def _reload(self) -> None:
        self.list.clear()
        self._entries = []
        repo = self._repo()
        local: list[CatalogEntry] = []
        try:
            local = load_local_catalog(self._recipes_dir)
        except CatalogError:
            local = []

        # Official repo is often private → raw.githubusercontent 404. Prefer local then.
        if repo == DEFAULT_GITHUB_REPO or not repo:
            try:
                self._entries = fetch_catalog_from_github(repo or DEFAULT_GITHUB_REPO)
                self.status.setText(t("catalog.loaded_github", n=len(self._entries)))
            except CatalogError:
                self._entries = local
                if self._entries:
                    self.status.setText(t("catalog.loaded_local", n=len(self._entries)))
                else:
                    self.status.setText(t("catalog.empty"))
                    return
        else:
            try:
                self._entries = fetch_catalog_from_github(repo)
                self.status.setText(t("catalog.loaded_github", n=len(self._entries)))
            except CatalogError as exc:
                self._entries = local
                if self._entries:
                    self.status.setText(t("catalog.foreign_fail_local", err=str(exc), n=len(self._entries)))
                else:
                    self.status.setText(str(exc))
                    return

        for entry in self._entries:
            badge = t("catalog.trust_official") if entry.is_official else t("catalog.trust_community")
            mark = " ✓" if entry.id in self._installed else ""
            item = QListWidgetItem(f"{entry.name}  [{badge}]{mark}")
            item.setData(Qt.ItemDataRole.UserRole, entry.id)
            tip = entry.summary.get("de") or entry.summary.get("en") or entry.category
            item.setToolTip(tip)
            self.list.addItem(item)

    def _remember_source(self) -> None:
        repo = self._repo()
        if not repo or repo == DEFAULT_GITHUB_REPO:
            return
        sources = list(self._settings.recipe_sources)
        if any(s.get("url") == repo or s.get("id") == repo for s in sources):
            self.status.setText(t("catalog.source_exists"))
            return
        if (
            QMessageBox.warning(
                self,
                t("catalog.title"),
                t("catalog.foreign_warn_dialog"),
                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
            )
            != QMessageBox.StandardButton.Yes
        ):
            return
        sources.append(
            {
                "id": repo.replace("/", "-"),
                "url": repo,
                "label": repo,
                "trusted": False,
            }
        )
        self._settings.recipe_sources = sources
        save_settings(self._settings)
        self.status.setText(t("catalog.source_saved"))

    def _install_selected(self) -> None:
        item = self.list.currentItem()
        if item is None:
            return
        rid = str(item.data(Qt.ItemDataRole.UserRole) or "")
        if not rid:
            return
        repo = self._repo() or DEFAULT_GITHUB_REPO
        if repo != DEFAULT_GITHUB_REPO:
            if (
                QMessageBox.warning(
                    self,
                    t("catalog.title"),
                    t("catalog.foreign_confirm", repo=repo),
                    QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
                )
                != QMessageBox.StandardButton.Yes
            ):
                return
        self.status.setText(t("catalog.installing", id=rid))
        try:
            dest = install_recipe_from_github(
                repo,
                rid,
                self._recipes_dir,
                catalog=self._entries,
            )
        except (RecipeInstallError, CatalogError) as exc:
            QMessageBox.critical(self, t("catalog.title"), str(exc))
            self.status.setText(str(exc))
            return
        self._installed.add(rid)
        self.status.setText(t("catalog.installed", path=str(dest)))
        self._reload()


class HiddenRecipesDialog(QDialog):
    """Show hidden recipe ids and restore them to the sidebar."""

    def __init__(
        self,
        parent: QWidget | None,
        *,
        settings: RezeptorSettings,
        recipe_names: dict[str, str],
    ) -> None:
        super().__init__(parent)
        self._settings = settings
        self._names = dict(recipe_names)
        self.setWindowTitle(t("hidden.title"))
        self.resize(420, 360)

        root = QVBoxLayout(self)
        intro = QLabel(t("hidden.intro"))
        intro.setWordWrap(True)
        intro.setObjectName("muted")
        root.addWidget(intro)

        self.list = QListWidget()
        root.addWidget(self.list, stretch=1)

        btn_row = QHBoxLayout()
        unhide_btn = QPushButton(t("hidden.unhide"))
        unhide_btn.clicked.connect(self._unhide_selected)
        btn_row.addWidget(unhide_btn)
        btn_row.addStretch(1)
        close_btn = QPushButton(t("catalog.close"))
        close_btn.clicked.connect(self.accept)
        btn_row.addWidget(close_btn)
        root.addLayout(btn_row)

        self._reload()

    def _reload(self) -> None:
        self.list.clear()
        hidden = list(self._settings.hidden_recipe_ids or [])
        if not hidden:
            item = QListWidgetItem(t("hidden.empty"))
            item.setFlags(Qt.ItemFlag.NoItemFlags)
            self.list.addItem(item)
            return
        for rid in hidden:
            label = self._names.get(rid, rid)
            item = QListWidgetItem(f"{label}  ({rid})")
            item.setData(Qt.ItemDataRole.UserRole, rid)
            self.list.addItem(item)

    def _unhide_selected(self) -> None:
        item = self.list.currentItem()
        if item is None:
            return
        rid = str(item.data(Qt.ItemDataRole.UserRole) or "")
        if not rid:
            return
        hidden = [h for h in (self._settings.hidden_recipe_ids or []) if h != rid]
        self._settings.hidden_recipe_ids = hidden
        save_settings(self._settings)
        self._reload()
