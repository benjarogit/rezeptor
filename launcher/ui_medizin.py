"""Medizin — lasting per-recipe options (not one-shot install actions)."""

from __future__ import annotations

from collections import OrderedDict
from pathlib import Path

from PyQt6.QtCore import QSize, Qt, QTimer
from PyQt6.QtGui import QAction, QCloseEvent
from PyQt6.QtWidgets import (
    QCheckBox,
    QComboBox,
    QDialog,
    QDialogButtonBox,
    QHBoxLayout,
    QLabel,
    QMenu,
    QScrollArea,
    QSizePolicy,
    QStackedWidget,
    QToolButton,
    QVBoxLayout,
    QWidget,
)

from i18n import get_locale, t
from recipe_options import (
    RecipeOption,
    migrate_photoshop_windows_like_ui,
    read_option_values,
    write_option_env,
    write_option_value,
)
from steam_proton_catalog import (
    curated_steam_proton_choices,
    is_steam_proton_option,
)
from trainer_deploy import (
    TrainerDeployError,
    deploy_trainer_source,
    installed_trainer_exe,
)
from ui_fluent import FLUENT_AVAILABLE, RoundMenu
from ui_icons import fa_icon
from ui_rezeptor import LimitedComboBox, SegmentTabBar
from ui_source import pick_directory, pick_open_file
from ui_styles import COLOR_PARCHMENT, MUTED, style_status_label
from ui_window import mark_force_close, mark_user_dismiss


# Options that need Repair after toggle (prefix/prefs already written).
_REPAIR_AFTER = frozenset(
    {
        "PREMIERE_NVIDIA_LIBS",
        "PHOTOSHOP_GENP_ON_REPAIR",
        "PHOTOSHOP_WINDOWS_LIKE_UI",
        "PHOTOSHOP_UI_HOME_SCREEN",
        "PHOTOSHOP_UI_RICH_TOOLTIPS",
        "PHOTOSHOP_UI_MODERN_NEW",
        "HALO_GFX_CLEAR_IMAGE",
        "HALO_GFX_EXCLUSIVE_FS",
        "HALO_GFX_VRAM_6GB",
        "HALO_GFX_VRR",
        "HALO_GFX_PRESET",
        "HALO_SKIP_INTRO",
        "HALO_MOD_VIEWMODELS",
        "HALO_MOD_HIDDEN_SKINS",
        "HALO_MOD_CLEAN_HUD",
        "HALO_MOD_SKULLS_UNLOCKED",
        "HALO_MOD_WEAPON_SLOTS_4",
        "HALO_MOD_THIRD_PERSON",
    }
)

_GROUP_ORDER = ("runtime", "graphics", "mods")


def option_group(opt: RecipeOption) -> str:
    """Tab bucket: recipe.yml ``group`` or infer from id/env."""
    g = (getattr(opt, "group", "") or "").strip().lower()
    if g in _GROUP_ORDER:
        return g
    key = f"{opt.env}_{opt.id}".upper()
    oid = (opt.id or "").lower()
    if (
        "GFX_" in key
        or oid.startswith("gfx_")
        or "GRAPHICS" in key
    ):
        return "graphics"
    if (
        "MOD_" in key
        or oid.startswith("mod_")
        or "SKIP_INTRO" in key
        or oid.startswith("skip_")
    ):
        return "mods"
    return "runtime"


def _group_label(key: str) -> str:
    return t(f"medizin.tab_{key}")


class MedizinDialog(QDialog):
    """Show recipe options with always-visible explanations (no menu tooltips).

    Many options → SegmentTabBar (runtime / graphics / mods). Few options → flat list.
    """

    def __init__(
        self,
        options: list[RecipeOption],
        data_root: Path,
        parent: QWidget | None = None,
    ) -> None:
        super().__init__(parent)
        self.setWindowTitle(t("medizin.dialog_title"))
        self.setMinimumWidth(420)
        self.setMaximumWidth(580)
        self._data_root = data_root
        self._options = options
        self._needs_repair_hint = False
        self._boxes: list[tuple[RecipeOption, QCheckBox]] = []
        self._combos: list[tuple[RecipeOption, QComboBox]] = []
        self._trainer_status: QLabel | None = None

        lay = QVBoxLayout(self)
        lay.setContentsMargins(16, 12, 16, 12)
        lay.setSpacing(8)

        intro = QLabel(t("medizin.dialog_intro"))
        intro.setWordWrap(True)
        intro.setObjectName("muted")
        intro.setSizePolicy(
            QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Preferred
        )
        self._style_muted(intro)
        lay.addWidget(intro)

        migrate_photoshop_windows_like_ui(data_root)
        values = read_option_values(data_root, options)
        locale = get_locale()

        grouped: OrderedDict[str, list[RecipeOption]] = OrderedDict()
        for key in _GROUP_ORDER:
            grouped[key] = []
        for opt in options:
            grouped.setdefault(option_group(opt), []).append(opt)
        # Drop empty groups; keep order
        groups = [(k, opts) for k, opts in grouped.items() if opts]
        use_tabs = len(groups) > 1

        if use_tabs:
            tabs = [(k, _group_label(k)) for k, _ in groups]
            self._seg = SegmentTabBar(tabs)
            self._stack = QStackedWidget()
            self._seg.tabSelected.connect(self._on_tab)
            lay.addWidget(self._seg)
            for _key, opts in groups:
                page = self._build_options_page(opts, values, locale)
                self._stack.addWidget(page)
            lay.addWidget(self._stack, stretch=1)
            self._seg.set_current(groups[0][0])
            self._tab_keys = [k for k, _ in groups]
        else:
            self._seg = None
            self._stack = None
            self._tab_keys = []
            page = self._build_options_page(
                groups[0][1] if groups else [], values, locale
            )
            lay.addWidget(page, stretch=1)

        self._hint = QLabel("")
        self._hint.setWordWrap(True)
        self._hint.setObjectName("statusHint")
        self._hint.setSizePolicy(
            QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Preferred
        )
        self._hint.setVisible(False)
        lay.addWidget(self._hint)

        buttons = QDialogButtonBox(QDialogButtonBox.StandardButton.Close)
        buttons.rejected.connect(self.reject)
        close_btn = buttons.button(QDialogButtonBox.StandardButton.Close)
        if close_btn is not None:
            close_btn.setText(t("medizin.close"))
            close_btn.clicked.connect(self.accept)
        lay.addWidget(buttons)

        if FLUENT_AVAILABLE:
            self.setObjectName("medizinDialog")

        self.adjustSize()
        hint = self.sizeHint()
        if hint.isValid():
            h = min(max(hint.height(), 280), 560)
            self.resize(max(420, min(hint.width() + 8, 580)), h)

    def _on_tab(self, key: str) -> None:
        if self._stack is None:
            return
        try:
            idx = self._tab_keys.index(key)
        except ValueError:
            return
        self._stack.setCurrentIndex(idx)
        if self._seg is not None:
            self._seg.set_current(key)

    def _build_options_page(
        self,
        opts: list[RecipeOption],
        values: dict[str, bool | str],
        locale: str,
    ) -> QWidget:
        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setFrameShape(QScrollArea.Shape.NoFrame)
        scroll.setHorizontalScrollBarPolicy(
            Qt.ScrollBarPolicy.ScrollBarAlwaysOff
        )
        host = QWidget()
        col = QVBoxLayout(host)
        col.setContentsMargins(0, 4, 4, 4)
        col.setSpacing(8)
        for opt in opts:
            block = QVBoxLayout()
            block.setSpacing(2)
            block.setContentsMargins(0, 0, 0, 0)

            if opt.type == "choice":
                title = QLabel(opt.label_for(locale))
                title.setWordWrap(True)
                block.addWidget(title)
                combo = LimitedComboBox(self, max_visible=8)
                for cid, lab in self._choice_items(opt, locale):
                    combo.addItem(lab, cid)
                current = str(values.get(opt.id, opt.default))
                idx = combo.findData(current)
                if idx < 0 and combo.count():
                    idx = 0
                    current = str(combo.itemData(0))
                if idx >= 0:
                    combo.setCurrentIndex(idx)
                combo.currentIndexChanged.connect(
                    lambda _i, o=opt, c=combo: self._on_choice(o, c)
                )
                block.addWidget(combo)
                self._combos.append((opt, combo))
            else:
                row = QHBoxLayout()
                row.setSpacing(4)
                row.setContentsMargins(0, 0, 0, 0)
                cb = QCheckBox(opt.label_for(locale))
                cb.setChecked(bool(values.get(opt.id, opt.default)))
                cb.toggled.connect(
                    lambda checked, o=opt: self._on_toggle(o, checked)
                )
                row.addWidget(cb, stretch=1)
                if opt.pick is not None:
                    row.addWidget(
                        self._make_pick_button(opt),
                        alignment=Qt.AlignmentFlag.AlignTop,
                    )
                block.addLayout(row)
                self._boxes.append((opt, cb))

                if opt.pick is not None:
                    status = QLabel(self._trainer_status_text())
                    status.setWordWrap(True)
                    status.setObjectName("muted")
                    status.setContentsMargins(22, 0, 0, 0)
                    self._style_muted(status)
                    self._trainer_status = status
                    block.addWidget(status)

            tip = QLabel(opt.tip_for(locale) or "")
            tip.setWordWrap(True)
            tip.setObjectName("muted")
            tip.setSizePolicy(
                QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Preferred
            )
            self._style_muted(tip)
            tip.setContentsMargins(22, 0, 0, 4)
            if tip.text().strip():
                block.addWidget(tip)
            wrap = QWidget()
            wrap.setSizePolicy(
                QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Preferred
            )
            wrap.setLayout(block)
            col.addWidget(wrap)
        col.addStretch(1)
        scroll.setWidget(host)
        return scroll

    def _choice_items(
        self, opt: RecipeOption, locale: str
    ) -> list[tuple[str, str]]:
        """(value, label) for combo — Steam Proton uses live host catalog."""
        if is_steam_proton_option(opt):
            code = (locale or "de").split("-", 1)[0].lower()
            items: list[tuple[str, str]] = []
            for c in curated_steam_proton_choices():
                lab = c.label_de if code == "de" else c.label_en
                items.append((c.tool, lab))
            if items:
                return items
        out: list[tuple[str, str]] = []
        for ch in opt.choices:
            out.append((ch.id, ch.label_for(locale)))
        return out

    def _on_choice(self, opt: RecipeOption, combo: QComboBox) -> None:
        val = combo.currentData()
        if val is None:
            return
        try:
            write_option_value(self._data_root, opt, str(val))
        except OSError as exc:
            self._set_status(
                t("medizin.error_body", error=str(exc)),
                "error",
            )
            return
        if opt.env in _REPAIR_AFTER:
            self._needs_repair_hint = True
            self._set_status(t("medizin.apply_repair_hint"), "warn")
        else:
            self._set_status(t("medizin.saved_ok"), "ok")

    def _make_pick_button(self, opt: RecipeOption) -> QToolButton:
        btn = QToolButton(self)
        btn.setObjectName("openPathBtn")
        btn.setAutoRaise(True)
        btn.setCursor(Qt.CursorShape.PointingHandCursor)
        btn.setFixedSize(26, 26)
        btn.setToolTip(t("medizin.trainer_pick_tip"))
        btn.setAccessibleName(t("medizin.trainer_pick_tip"))
        folder_ic = fa_icon("folder", 14, color=COLOR_PARCHMENT)
        if folder_ic is not None:
            btn.setIcon(folder_ic)
            btn.setIconSize(QSize(14, 14))
        else:
            btn.setText("…")
        btn.clicked.connect(lambda _c=False, o=opt, b=btn: self._popup_pick_menu(o, b))
        return btn

    def _popup_pick_menu(self, opt: RecipeOption, btn: QToolButton) -> None:
        menu = RoundMenu(parent=self) if FLUENT_AVAILABLE else QMenu(self)
        self._add_menu_action(
            menu,
            t("medizin.trainer_pick_exe"),
            lambda _c=False, o=opt: self._pick_trainer_exe(o),
        )
        self._add_menu_action(
            menu,
            t("medizin.trainer_pick_folder"),
            lambda _c=False, o=opt: self._pick_trainer_folder(o),
        )
        pos = btn.mapToGlobal(btn.rect().bottomLeft())
        QTimer.singleShot(0, lambda p=pos, m=menu: m.exec(p))

    @staticmethod
    def _add_menu_action(menu: QMenu, text: str, slot) -> QAction:  # noqa: ANN001
        action = QAction(text, menu)
        action.triggered.connect(slot)
        menu.addAction(action)
        return action

    def _pick_trainer_exe(self, opt: RecipeOption) -> None:
        start = str(Path.home() / "Downloads")
        path = pick_open_file(
            self,
            t("medizin.trainer_pick_exe"),
            start,
            "Windows EXE (*.exe);;All (*)",
        )
        if not path:
            self._set_status(t("medizin.trainer_pick_cancel"), "info")
            return
        self._deploy_picked(opt, Path(path))

    def _pick_trainer_folder(self, opt: RecipeOption) -> None:
        start = str(Path.home() / "Downloads")
        path = pick_directory(self, t("medizin.trainer_pick_folder"), start)
        if not path:
            self._set_status(t("medizin.trainer_pick_cancel"), "info")
            return
        self._deploy_picked(opt, Path(path))

    def _deploy_picked(self, opt: RecipeOption, source: Path) -> None:
        try:
            deployed = deploy_trainer_source(self._data_root, source)
        except (TrainerDeployError, OSError) as exc:
            self._set_status(
                t("medizin.trainer_pick_error", error=str(exc)),
                "error",
            )
            return
        try:
            write_option_value(self._data_root, opt, True)
            if opt.pick and opt.pick.source_env:
                write_option_env(
                    self._data_root, opt.pick.source_env, str(source)
                )
        except (OSError, ValueError) as exc:
            self._set_status(
                t("medizin.error_body", error=str(exc)),
                "error",
            )
            return
        for o, cb in self._boxes:
            if o.id == opt.id:
                cb.blockSignals(True)
                cb.setChecked(True)
                cb.blockSignals(False)
                break
        if self._trainer_status is not None:
            self._trainer_status.setText(self._trainer_status_text())
        self._set_status(
            t("medizin.trainer_ready", name=deployed.name),
            "ok",
        )

    def _trainer_status_text(self) -> str:
        exe = installed_trainer_exe(self._data_root)
        if exe is None:
            return t("medizin.trainer_none")
        return t("medizin.trainer_ready", name=exe.name)

    @staticmethod
    def _style_muted(label: QLabel) -> None:
        label.setStyleSheet(
            f"color: {MUTED}; font-size: 12px; background: transparent;"
        )

    def _set_status(self, text: str, kind: str) -> None:
        self._hint.setText(text)
        style_status_label(self._hint, kind)
        self._hint.setVisible(bool(text.strip()))

    def _on_toggle(self, opt: RecipeOption, checked: bool) -> None:
        try:
            write_option_value(self._data_root, opt, checked)
        except OSError as exc:
            self._set_status(
                t("medizin.error_body", error=str(exc)),
                "error",
            )
            return
        if opt.env in _REPAIR_AFTER:
            self._needs_repair_hint = True
            self._set_status(t("medizin.apply_repair_hint"), "warn")
        else:
            self._set_status(t("medizin.saved_ok"), "ok")

    @property
    def needs_repair_hint(self) -> bool:
        return self._needs_repair_hint

    def accept(self) -> None:
        mark_user_dismiss(self)
        super().accept()

    def reject(self) -> None:
        if getattr(self, "_rezeptor_force_close", False) or self.property(
            "rezeptor_force_close"
        ):
            super().reject()
            return
        mark_user_dismiss(self)
        super().reject()

    def force_close(self) -> None:
        mark_force_close(self)
        self.done(QDialog.DialogCode.Rejected)

    def closeEvent(self, event: QCloseEvent) -> None:  # noqa: N802
        if getattr(self, "_rezeptor_force_close", False) or self.property(
            "rezeptor_force_close"
        ):
            super().closeEvent(event)
            return
        mark_user_dismiss(self)
        super().closeEvent(event)
