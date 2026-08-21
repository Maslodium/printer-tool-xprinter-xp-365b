# Xprinter Label Editor

Small Windows PowerShell/WinForms label editor for Xprinter XP-365B and compatible TSPL thermal label printers.

## Features

- Direct TSPL bitmap printing, bypassing Windows page layout scaling issues.
- Default label size: 57 x 39 mm at 203 DPI.
- Text editor with font selection from installed Windows fonts.
- No-wrap mode for short labels.
- Preview based on the exact bitmap sent to the printer.
- Image import with automatic downsampling for large images.
- Image scale and alignment controls.
- Label feed, home, and gap calibration commands.

## Requirements

- Windows PowerShell 5.1
- Windows Forms and System.Drawing
- Installed Xprinter XP-365B printer driver
- Printer connected as a Windows printer, default name: `Xprinter XP-365B`

## Run

```powershell
powershell -STA -NoProfile -ExecutionPolicy Bypass -File .\LabelPrinter.ps1
```

## Notes

The printer is treated as a RAW TSPL output device for actual printing. The Windows printer driver is used only as a transport channel to the USB printer.

Large images are downsampled to a working copy before being fitted into the 203 DPI label bitmap, so high-resolution images can be used safely.
