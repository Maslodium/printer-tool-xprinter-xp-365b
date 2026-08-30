# XPrinter XP-365B Label Tool

Windows label editor for the Xprinter XP-365B and compatible TSPL thermal label printers.

The tool renders the label as a 203 DPI bitmap and sends it to the selected Windows printer queue as RAW TSPL data. This avoids Windows page scaling problems and makes 57 x 39 mm labels print in the same proportions as the preview.

Maintained by Maslodium.

## Features

- Real-size preview for 57 x 39 mm labels.
- Direct TSPL bitmap printing through a normal Windows printer or shared printer.
- Text editor with installed Windows fonts, bold, italic, underline and strikeout.
- Text undo/redo: `Ctrl+Z` and `Ctrl+Shift+Z`.
- No-wrap mode for short one-line labels.
- Image import with automatic downscaling for large files.
- Drag-and-drop image loading.
- Image paste from clipboard with `Ctrl+V` or the `Paste image` button.
- Image scaling and horizontal/vertical alignment.
- Home, Feed label and Calibrate commands for label roll positioning.

## Requirements

- Windows PowerShell 5.1 or the packaged `.exe` build.
- Xprinter XP-365B driver or a compatible RAW-capable Windows printer queue.
- A Windows printer name such as `Xprinter XP-365B` or a normal shared queue like `\\HOST\XPrinter_XP365B`.

## Run From Source

```powershell
powershell -STA -NoProfile -ExecutionPolicy Bypass -File .\LabelPrinter.ps1
```

## Notes

The printer is used as a RAW TSPL device. The Windows printer driver is only the transport to the USB or shared printer.

Large images are copied into memory and reduced to a maximum 1200 px working copy before they are fitted into the final 203 DPI label bitmap, so oversized source images do not get sent to the printer directly.

---

# Средство для печати Xprinter XP-365B

Windows-редактор этикеток для Xprinter XP-365B и совместимых TSPL термопринтеров.

Программа собирает этикетку как bitmap 203 DPI и отправляет её в выбранную очередь печати Windows как RAW TSPL. За счёт этого не включается масштабирование страниц Windows, а этикетка 57 x 39 мм печатается в тех же пропорциях, что показаны в предпросмотре.

Поддерживает Maslodium.

## Возможности

- Предпросмотр по реальным пропорциям этикетки 57 x 39 мм.
- Прямая TSPL bitmap-печать через обычный Windows-принтер или сетевую шару.
- Редактор текста с установленными шрифтами Windows, жирным, курсивом, подчёркиванием и зачёркиванием.
- Отмена и повтор текста: `Ctrl+Z` и `Ctrl+Shift+Z`.
- Режим No wrap для коротких однострочных этикеток.
- Импорт изображений с автоматическим уменьшением больших файлов.
- Загрузка изображения drag-and-drop.
- Вставка изображения из буфера обмена через `Ctrl+V` или кнопку `Paste image`.
- Масштаб и выравнивание изображения.
- Команды Home, Feed label и Calibrate для подачи и калибровки этикеток.

## Требования

- Windows PowerShell 5.1 или собранный `.exe`.
- Драйвер Xprinter XP-365B или совместимая RAW-очередь печати Windows.
- Имя принтера Windows, например `Xprinter XP-365B`, либо обычная сетевая очередь вида `\\HOST\XPrinter_XP365B`.

## Запуск из исходников

```powershell
powershell -STA -NoProfile -ExecutionPolicy Bypass -File .\LabelPrinter.ps1
```

## Примечания

Принтер используется как RAW TSPL-устройство. Windows-драйвер нужен только как транспорт до USB-принтера или сетевой шары.

Большие изображения копируются в память и уменьшаются до рабочей копии максимум 1200 px по длинной стороне, а затем вписываются в финальную bitmap-картинку этикетки 203 DPI.
