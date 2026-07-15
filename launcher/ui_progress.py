"""Animierter Warte-Spinner (QtWaitingSpinner-Muster, ohne Extra-Paket)."""

from __future__ import annotations

from PyQt6.QtCore import QRectF, Qt, QTimer
from PyQt6.QtGui import QColor, QPainter, QPen
from PyQt6.QtWidgets import QWidget

from ui_fluent import ACCENT_COPPER


class WaitingSpinner(QWidget):
    """Drehender Arc — sichtbar und animiert solange start() aktiv ist."""

    def __init__(self, parent: QWidget | None = None, *, size: int = 18) -> None:
        super().__init__(parent)
        self._size = size
        self._angle = 0
        self.setFixedSize(size, size)
        self._timer = QTimer(self)
        self._timer.setInterval(40)
        self._timer.timeout.connect(self._tick)
        self.hide()

    def _tick(self) -> None:
        self._angle = (self._angle + 18) % 360
        self.update()

    def start(self) -> None:
        self.show()
        if not self._timer.isActive():
            self._timer.start()

    def stop(self) -> None:
        self._timer.stop()
        self.hide()

    def paintEvent(self, _event) -> None:  # type: ignore[no-untyped-def]
        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)
        # Track
        track = QPen(QColor("#3e3e42"))
        track.setWidth(2)
        painter.setPen(track)
        margin = 2
        rect = QRectF(margin, margin, self._size - 2 * margin, self._size - 2 * margin)
        painter.drawEllipse(rect)
        # Arc
        pen = QPen(QColor(ACCENT_COPPER))
        pen.setWidth(2)
        pen.setCapStyle(Qt.PenCapStyle.RoundCap)
        painter.setPen(pen)
        painter.drawArc(rect, -self._angle * 16, 270 * 16)
