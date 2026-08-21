param(
    [string]$Text = "LABEL TEXT",
    [string]$PrinterName = "Xprinter XP-365B",
    [string]$FontFamily = "ST MicroSquare Ex",
    [int]$FontSize = 13,
    [double]$LabelWidthMm = 57,
    [double]$LabelHeightMm = 39,
    [double]$GapMm = 3,
    [double]$MarginMm = 4,
    [double]$OffsetXmm = 0,
    [double]$OffsetYmm = 0,
    [string]$HorizontalAlign = "Center",
    [string]$VerticalAlign = "Middle",
    [bool]$NoWrap = $true,
    [int]$Copies = 1,
    [switch]$PrintNow
)

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

$rawPrinterSource = @"
using System;
using System.Runtime.InteropServices;

public class RawPrinterHelper {
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Ansi)]
    public class DOCINFOA {
        [MarshalAs(UnmanagedType.LPStr)] public string pDocName;
        [MarshalAs(UnmanagedType.LPStr)] public string pOutputFile;
        [MarshalAs(UnmanagedType.LPStr)] public string pDataType;
    }

    [DllImport("winspool.Drv", EntryPoint="OpenPrinterA", SetLastError=true, CharSet=CharSet.Ansi, ExactSpelling=true, CallingConvention=CallingConvention.StdCall)]
    public static extern bool OpenPrinter(string szPrinter, out IntPtr hPrinter, IntPtr pd);

    [DllImport("winspool.Drv", EntryPoint="ClosePrinter", SetLastError=true, ExactSpelling=true, CallingConvention=CallingConvention.StdCall)]
    public static extern bool ClosePrinter(IntPtr hPrinter);

    [DllImport("winspool.Drv", EntryPoint="StartDocPrinterA", SetLastError=true, CharSet=CharSet.Ansi, ExactSpelling=true, CallingConvention=CallingConvention.StdCall)]
    public static extern bool StartDocPrinter(IntPtr hPrinter, Int32 level, [In, MarshalAs(UnmanagedType.LPStruct)] DOCINFOA di);

    [DllImport("winspool.Drv", EntryPoint="EndDocPrinter", SetLastError=true, ExactSpelling=true, CallingConvention=CallingConvention.StdCall)]
    public static extern bool EndDocPrinter(IntPtr hPrinter);

    [DllImport("winspool.Drv", EntryPoint="StartPagePrinter", SetLastError=true, ExactSpelling=true, CallingConvention=CallingConvention.StdCall)]
    public static extern bool StartPagePrinter(IntPtr hPrinter);

    [DllImport("winspool.Drv", EntryPoint="EndPagePrinter", SetLastError=true, ExactSpelling=true, CallingConvention=CallingConvention.StdCall)]
    public static extern bool EndPagePrinter(IntPtr hPrinter);

    [DllImport("winspool.Drv", EntryPoint="WritePrinter", SetLastError=true, ExactSpelling=true, CallingConvention=CallingConvention.StdCall)]
    public static extern bool WritePrinter(IntPtr hPrinter, byte[] pBytes, Int32 dwCount, out Int32 dwWritten);

    public static bool SendBytes(string printerName, byte[] bytes, string documentName) {
        IntPtr hPrinter;
        if (!OpenPrinter(printerName.Normalize(), out hPrinter, IntPtr.Zero)) return false;
        DOCINFOA di = new DOCINFOA();
        di.pDocName = documentName;
        di.pDataType = "RAW";
        bool ok = false;
        try {
            if (StartDocPrinter(hPrinter, 1, di)) {
                if (StartPagePrinter(hPrinter)) {
                    int written;
                    ok = WritePrinter(hPrinter, bytes, bytes.Length, out written);
                    EndPagePrinter(hPrinter);
                }
                EndDocPrinter(hPrinter);
            }
        }
        finally {
            ClosePrinter(hPrinter);
        }
        return ok;
    }
}
"@

if (-not ("RawPrinterHelper" -as [type])) {
    Add-Type -TypeDefinition $rawPrinterSource
}

function Convert-MmToHundredthsInch([double]$mm) {
    return [int][Math]::Round($mm / 25.4 * 100)
}

function Convert-MmToDots([double]$mm) {
    return [int][Math]::Round($mm * 203 / 25.4)
}

function Format-Mm([double]$mm) {
    return $mm.ToString("0.###", [System.Globalization.CultureInfo]::InvariantCulture)
}

function Test-FontFamily([string]$name) {
    $fonts = New-Object System.Drawing.Text.InstalledFontCollection
    return [bool]($fonts.Families | Where-Object { $_.Name -eq $name })
}

function Get-AlignValue([string]$value, [string]$axis) {
    if ($axis -eq "H") {
        if ($value -eq "Left") { return [System.Drawing.StringAlignment]::Near }
        if ($value -eq "Right") { return [System.Drawing.StringAlignment]::Far }
        return [System.Drawing.StringAlignment]::Center
    }
    if ($value -eq "Top") { return [System.Drawing.StringAlignment]::Near }
    if ($value -eq "Bottom") { return [System.Drawing.StringAlignment]::Far }
    return [System.Drawing.StringAlignment]::Center
}

function Get-TextRectangle {
    param(
        [System.Drawing.RectangleF]$PageRect,
        [double]$UnitsPerMm,
        [double]$InsetMm,
        [double]$Xmm,
        [double]$Ymm
    )

    $left = $PageRect.Left + (($InsetMm + $Xmm) * $UnitsPerMm)
    $top = $PageRect.Top + (($InsetMm + $Ymm) * $UnitsPerMm)
    $right = $PageRect.Right - ($InsetMm * $UnitsPerMm)
    $bottom = $PageRect.Bottom - ($InsetMm * $UnitsPerMm)
    $width = [Math]::Max(1, $right - $left)
    $height = [Math]::Max(1, $bottom - $top)
    return New-Object System.Drawing.RectangleF($left, $top, $width, $height)
}

function Draw-LabelContent {
    param(
        [System.Drawing.Graphics]$Graphics,
        [System.Drawing.RectangleF]$PageRect,
        [double]$UnitsPerMm,
        [string]$LabelText,
        [System.Drawing.Image]$LabelImage,
        [int]$ImageScalePercent,
        [string]$ImageHAlign,
        [string]$ImageVAlign,
        [string]$Family,
        [int]$Size,
        [double]$InsetMm,
        [double]$Xmm,
        [double]$Ymm,
        [string]$HAlign,
        [string]$VAlign,
        [bool]$DisableWrap,
        [bool]$Preview
    )

    $Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $Graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit

    if ($Preview) {
        $Graphics.Clear([System.Drawing.Color]::FromArgb(245, 246, 248))
        $labelBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
        $borderPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(35, 35, 35), 1)
        $safePen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(190, 80, 80), 1)
        $safePen.DashStyle = [System.Drawing.Drawing2D.DashStyle]::Dash
        try {
            $Graphics.FillRectangle($labelBrush, $PageRect)
            $Graphics.DrawRectangle($borderPen, $PageRect.X, $PageRect.Y, $PageRect.Width, $PageRect.Height)
        }
        finally {
            $labelBrush.Dispose()
            $borderPen.Dispose()
        }
    }
    else {
        $Graphics.Clear([System.Drawing.Color]::White)
    }

    $textRect = Get-TextRectangle -PageRect $PageRect -UnitsPerMm $UnitsPerMm -InsetMm $InsetMm -Xmm $Xmm -Ymm $Ymm

    if ($LabelImage -ne $null) {
        $maxImageW = $textRect.Width * ([Math]::Max(5, $ImageScalePercent) / 100.0)
        $maxImageH = $textRect.Height * ([Math]::Max(5, $ImageScalePercent) / 100.0)
        $imageScale = [Math]::Min($maxImageW / $LabelImage.Width, $maxImageH / $LabelImage.Height)
        if ($imageScale -gt 0) {
            $imageW = $LabelImage.Width * $imageScale
            $imageH = $LabelImage.Height * $imageScale
            $imageX = $textRect.Left
            $imageY = $textRect.Top
            if ($ImageHAlign -eq "Center") { $imageX = $textRect.Left + (($textRect.Width - $imageW) / 2) }
            if ($ImageHAlign -eq "Right") { $imageX = $textRect.Right - $imageW }
            if ($ImageVAlign -eq "Middle") { $imageY = $textRect.Top + (($textRect.Height - $imageH) / 2) }
            if ($ImageVAlign -eq "Bottom") { $imageY = $textRect.Bottom - $imageH }

            $imageRect = New-Object System.Drawing.RectangleF($imageX, $imageY, $imageW, $imageH)
            $oldInterpolation = $Graphics.InterpolationMode
            $oldCompositing = $Graphics.CompositingQuality
            try {
                $Graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $Graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
                $Graphics.DrawImage($LabelImage, $imageRect)
            }
            finally {
                $Graphics.InterpolationMode = $oldInterpolation
                $Graphics.CompositingQuality = $oldCompositing
            }
        }
    }

    if ($Preview) {
        $safePen2 = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(190, 80, 80), 1)
        $safePen2.DashStyle = [System.Drawing.Drawing2D.DashStyle]::Dash
        try {
            $Graphics.DrawRectangle($safePen2, $textRect.X, $textRect.Y, $textRect.Width, $textRect.Height)
        }
        finally {
            $safePen2.Dispose()
        }
    }

    $format = New-Object System.Drawing.StringFormat
    $format.Alignment = Get-AlignValue $HAlign "H"
    $format.LineAlignment = Get-AlignValue $VAlign "V"
    $format.Trimming = [System.Drawing.StringTrimming]::EllipsisCharacter
    if ($DisableWrap) {
        $format.FormatFlags = [System.Drawing.StringFormatFlags]::NoWrap
    }

    $fontStyle = [System.Drawing.FontStyle]::Bold
    $drawSize = [Math]::Max(6, $Size)
    $font = New-Object System.Drawing.Font($Family, $drawSize, $fontStyle, [System.Drawing.GraphicsUnit]::Point)

    try {
        for ($i = 0; $i -lt 24; $i++) {
            $measured = $Graphics.MeasureString($LabelText, $font, [System.Drawing.SizeF]::new($textRect.Width, $textRect.Height), $format)
            if (($measured.Width -le $textRect.Width -and $measured.Height -le $textRect.Height) -or $drawSize -le 6) {
                break
            }
            $font.Dispose()
            $drawSize -= 1
            $font = New-Object System.Drawing.Font($Family, $drawSize, $fontStyle, [System.Drawing.GraphicsUnit]::Point)
        }
        $Graphics.DrawString($LabelText, $font, [System.Drawing.Brushes]::Black, $textRect, $format)
    }
    finally {
        $font.Dispose()
        $format.Dispose()
    }
}

function Send-RawPrinterText {
    param(
        [string]$TargetPrinter,
        [string]$Commands,
        [string]$DocumentName
    )

    if (-not (Get-Printer -Name $TargetPrinter -ErrorAction SilentlyContinue)) {
        throw "Printer '$TargetPrinter' was not found."
    }

    $bytes = [System.Text.Encoding]::ASCII.GetBytes($Commands)
    $ok = [RawPrinterHelper]::SendBytes($TargetPrinter, $bytes, $DocumentName)
    if (-not $ok) {
        throw "Raw printer command failed. Check printer mode and driver."
    }
}

function Send-RawPrinterBytes {
    param(
        [string]$TargetPrinter,
        [byte[]]$Bytes,
        [string]$DocumentName
    )

    if (-not (Get-Printer -Name $TargetPrinter -ErrorAction SilentlyContinue)) {
        throw "Printer '$TargetPrinter' was not found."
    }

    $ok = [RawPrinterHelper]::SendBytes($TargetPrinter, $Bytes, $DocumentName)
    if (-not $ok) {
        throw "Raw printer bytes failed. Check printer mode and driver."
    }
}

function Send-LabelHome {
    param(
        [string]$TargetPrinter,
        [double]$WidthMm,
        [double]$HeightMm,
        [double]$MediaGapMm
    )

    $widthText = Format-Mm $WidthMm
    $heightText = Format-Mm $HeightMm
    $gapText = Format-Mm $MediaGapMm
    $cmd = "SIZE $widthText mm,$heightText mm`r`nGAP $gapText mm,0`r`nDIRECTION 1`r`nHOME`r`n"
    Send-RawPrinterText -TargetPrinter $TargetPrinter -Commands $cmd -DocumentName "Label home"
}

function Send-LabelFeed {
    param(
        [string]$TargetPrinter,
        [double]$WidthMm,
        [double]$HeightMm,
        [double]$MediaGapMm
    )

    $widthText = Format-Mm $WidthMm
    $heightText = Format-Mm $HeightMm
    $gapText = Format-Mm $MediaGapMm
    $cmd = "SIZE $widthText mm,$heightText mm`r`nGAP $gapText mm,0`r`nDIRECTION 1`r`nFORMFEED`r`n"
    Send-RawPrinterText -TargetPrinter $TargetPrinter -Commands $cmd -DocumentName "Label feed"
}

function Send-LabelCalibration {
    param(
        [string]$TargetPrinter,
        [double]$WidthMm,
        [double]$HeightMm,
        [double]$MediaGapMm
    )

    $widthText = Format-Mm $WidthMm
    $heightText = Format-Mm $HeightMm
    $gapText = Format-Mm $MediaGapMm
    $cmd = "SIZE $widthText mm,$heightText mm`r`nGAP $gapText mm,0`r`nGAPDETECT`r`nHOME`r`n"
    Send-RawPrinterText -TargetPrinter $TargetPrinter -Commands $cmd -DocumentName "Label gap calibration"
}

function Convert-BitmapToTsplBytes {
    param(
        [System.Drawing.Bitmap]$Bitmap
    )

    $widthBytes = [int][Math]::Ceiling($Bitmap.Width / 8)
    $data = New-Object byte[] ($widthBytes * $Bitmap.Height)
    for ($i = 0; $i -lt $data.Length; $i++) {
        $data[$i] = 255
    }

    for ($y = 0; $y -lt $Bitmap.Height; $y++) {
        for ($x = 0; $x -lt $Bitmap.Width; $x++) {
            $pixel = $Bitmap.GetPixel($x, $y)
            $brightness = (($pixel.R * 0.299) + ($pixel.G * 0.587) + ($pixel.B * 0.114))
            if ($brightness -lt 170) {
                $byteIndex = ($y * $widthBytes) + [int][Math]::Floor($x / 8)
                $bit = 7 - ($x % 8)
                $data[$byteIndex] = $data[$byteIndex] -band (-bnot (1 -shl $bit))
            }
        }
    }

    return $data
}

function New-EditorImageCopy {
    param(
        [string]$Path
    )

    $source = [System.Drawing.Image]::FromFile($Path)
    try {
        $maxSide = 1200
        $scale = [Math]::Min(1.0, $maxSide / [double][Math]::Max($source.Width, $source.Height))
        $targetWidth = [Math]::Max(1, [int][Math]::Round($source.Width * $scale))
        $targetHeight = [Math]::Max(1, [int][Math]::Round($source.Height * $scale))

        $copy = New-Object System.Drawing.Bitmap($targetWidth, $targetHeight, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
        $copy.SetResolution(203, 203)
        $graphics = [System.Drawing.Graphics]::FromImage($copy)
        try {
            $graphics.Clear([System.Drawing.Color]::White)
            $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
            $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $graphics.DrawImage($source, 0, 0, $targetWidth, $targetHeight)
        }
        finally {
            $graphics.Dispose()
        }
        return $copy
    }
    finally {
        $source.Dispose()
    }
}

function New-LabelBitmap {
    param(
        [string]$LabelText,
        [System.Drawing.Image]$LabelImage,
        [int]$ImageScalePercent,
        [string]$ImageHAlign,
        [string]$ImageVAlign,
        [string]$Family,
        [int]$Size,
        [double]$WidthMm,
        [double]$HeightMm,
        [double]$InsetMm,
        [double]$Xmm,
        [double]$Ymm,
        [string]$HAlign,
        [string]$VAlign,
        [bool]$DisableWrap
    )

    $widthDots = Convert-MmToDots $WidthMm
    $heightDots = Convert-MmToDots $HeightMm
    $bitmap = New-Object System.Drawing.Bitmap($widthDots, $heightDots, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $bitmap.SetResolution(203, 203)

    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $pageRect = New-Object System.Drawing.RectangleF(0, 0, $widthDots, $heightDots)
        Draw-LabelContent `
            -Graphics $graphics `
            -PageRect $pageRect `
            -UnitsPerMm (203 / 25.4) `
            -LabelText $LabelText `
            -LabelImage $LabelImage `
            -ImageScalePercent $ImageScalePercent `
            -ImageHAlign $ImageHAlign `
            -ImageVAlign $ImageVAlign `
            -Family $Family `
            -Size $Size `
            -InsetMm $InsetMm `
            -Xmm $Xmm `
            -Ymm $Ymm `
            -HAlign $HAlign `
            -VAlign $VAlign `
            -DisableWrap $DisableWrap `
            -Preview $false
    }
    finally {
        $graphics.Dispose()
    }

    return $bitmap
}

function Draw-PrinterBitmapPreview {
    param(
        [System.Drawing.Graphics]$Graphics,
        [System.Windows.Forms.Control]$PreviewHost,
        [string]$LabelText,
        [System.Drawing.Image]$LabelImage,
        [int]$ImageScalePercent,
        [string]$ImageHAlign,
        [string]$ImageVAlign,
        [string]$Family,
        [int]$Size,
        [double]$WidthMm,
        [double]$HeightMm,
        [double]$InsetMm,
        [double]$Xmm,
        [double]$Ymm,
        [string]$HAlign,
        [string]$VAlign,
        [bool]$DisableWrap
    )

    $Graphics.Clear([System.Drawing.Color]::FromArgb(245, 246, 248))

    $bitmap = New-LabelBitmap -LabelText $LabelText -LabelImage $LabelImage -ImageScalePercent $ImageScalePercent -ImageHAlign $ImageHAlign -ImageVAlign $ImageVAlign -Family $Family -Size $Size -WidthMm $WidthMm -HeightMm $HeightMm -InsetMm $InsetMm -Xmm $Xmm -Ymm $Ymm -HAlign $HAlign -VAlign $VAlign -DisableWrap $DisableWrap
    try {
        $scale = [Math]::Min(($PreviewHost.ClientSize.Width - 36) / $bitmap.Width, ($PreviewHost.ClientSize.Height - 36) / $bitmap.Height)
        $drawW = $bitmap.Width * $scale
        $drawH = $bitmap.Height * $scale
        $x = ($PreviewHost.ClientSize.Width - $drawW) / 2
        $y = ($PreviewHost.ClientSize.Height - $drawH) / 2
        $dest = New-Object System.Drawing.RectangleF($x, $y, $drawW, $drawH)

        $Graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
        $Graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
        $Graphics.DrawImage($bitmap, $dest)

        $borderPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(35, 35, 35), 1)
        try {
            $Graphics.DrawRectangle($borderPen, $dest.X, $dest.Y, $dest.Width, $dest.Height)
        }
        finally {
            $borderPen.Dispose()
        }

        $textRectDots = Get-TextRectangle -PageRect (New-Object System.Drawing.RectangleF(0, 0, $bitmap.Width, $bitmap.Height)) -UnitsPerMm (203 / 25.4) -InsetMm $InsetMm -Xmm $Xmm -Ymm $Ymm
        $safePen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(190, 80, 80), 1)
        $safePen.DashStyle = [System.Drawing.Drawing2D.DashStyle]::Dash
        try {
            $safeRect = New-Object System.Drawing.RectangleF(
                ($dest.X + ($textRectDots.X * $scale)),
                ($dest.Y + ($textRectDots.Y * $scale)),
                ($textRectDots.Width * $scale),
                ($textRectDots.Height * $scale)
            )
            $Graphics.DrawRectangle($safePen, $safeRect.X, $safeRect.Y, $safeRect.Width, $safeRect.Height)
        }
        finally {
            $safePen.Dispose()
        }
    }
    finally {
        $bitmap.Dispose()
    }
}

function Invoke-TsplBitmapPrint {
    param(
        [string]$LabelText,
        [System.Drawing.Image]$LabelImage,
        [int]$ImageScalePercent,
        [string]$ImageHAlign,
        [string]$ImageVAlign,
        [string]$TargetPrinter,
        [string]$Family,
        [int]$Size,
        [double]$WidthMm,
        [double]$HeightMm,
        [double]$MediaGapMm,
        [double]$InsetMm,
        [double]$Xmm,
        [double]$Ymm,
        [string]$HAlign,
        [string]$VAlign,
        [bool]$DisableWrap,
        [int]$CopyCount
    )

    if (-not (Get-Printer -Name $TargetPrinter -ErrorAction SilentlyContinue)) {
        throw "Printer '$TargetPrinter' was not found."
    }

    if (-not (Test-FontFamily $Family)) {
        throw "Font '$Family' was not found."
    }

    $bitmap = New-LabelBitmap -LabelText $LabelText -LabelImage $LabelImage -ImageScalePercent $ImageScalePercent -ImageHAlign $ImageHAlign -ImageVAlign $ImageVAlign -Family $Family -Size $Size -WidthMm $WidthMm -HeightMm $HeightMm -InsetMm $InsetMm -Xmm $Xmm -Ymm $Ymm -HAlign $HAlign -VAlign $VAlign -DisableWrap $DisableWrap
    try {
        $imageBytes = Convert-BitmapToTsplBytes -Bitmap $bitmap
        $widthBytes = [int][Math]::Ceiling($bitmap.Width / 8)
        $heightDots = $bitmap.Height
        $widthText = Format-Mm $WidthMm
        $heightText = Format-Mm $HeightMm
        $gapText = Format-Mm $MediaGapMm
        $copiesText = [Math]::Max(1, $CopyCount).ToString([System.Globalization.CultureInfo]::InvariantCulture)

        $head = "SIZE $widthText mm,$heightText mm`r`nGAP $gapText mm,0`r`nDIRECTION 1`r`nREFERENCE 0,0`r`nOFFSET 0 mm`r`nCLS`r`nBITMAP 0,0,$widthBytes,$heightDots,0,"
        $tail = "`r`nPRINT $copiesText`r`n"
        $headBytes = [System.Text.Encoding]::ASCII.GetBytes($head)
        $tailBytes = [System.Text.Encoding]::ASCII.GetBytes($tail)
        $allBytes = New-Object byte[] ($headBytes.Length + $imageBytes.Length + $tailBytes.Length)
        [Array]::Copy($headBytes, 0, $allBytes, 0, $headBytes.Length)
        [Array]::Copy($imageBytes, 0, $allBytes, $headBytes.Length, $imageBytes.Length)
        [Array]::Copy($tailBytes, 0, $allBytes, $headBytes.Length + $imageBytes.Length, $tailBytes.Length)

        Send-RawPrinterBytes -TargetPrinter $TargetPrinter -Bytes $allBytes -DocumentName "TSPL bitmap label"
    }
    finally {
        $bitmap.Dispose()
    }
}

function Invoke-LabelPrint {
    param(
        [string]$LabelText,
        [System.Drawing.Image]$LabelImage,
        [int]$ImageScalePercent,
        [string]$ImageHAlign,
        [string]$ImageVAlign,
        [string]$TargetPrinter,
        [string]$Family,
        [int]$Size,
        [double]$WidthMm,
        [double]$HeightMm,
        [double]$MediaGapMm,
        [double]$InsetMm,
        [double]$Xmm,
        [double]$Ymm,
        [string]$HAlign,
        [string]$VAlign,
        [bool]$DisableWrap,
        [int]$CopyCount
    )

    Invoke-TsplBitmapPrint -LabelText $LabelText -LabelImage $LabelImage -ImageScalePercent $ImageScalePercent -ImageHAlign $ImageHAlign -ImageVAlign $ImageVAlign -TargetPrinter $TargetPrinter -Family $Family -Size $Size -WidthMm $WidthMm -HeightMm $HeightMm -MediaGapMm $MediaGapMm -InsetMm $InsetMm -Xmm $Xmm -Ymm $Ymm -HAlign $HAlign -VAlign $VAlign -DisableWrap $DisableWrap -CopyCount $CopyCount
}

if ($PrintNow) {
    Invoke-LabelPrint -LabelText $Text -LabelImage $null -ImageScalePercent 100 -ImageHAlign "Center" -ImageVAlign "Middle" -TargetPrinter $PrinterName -Family $FontFamily -Size $FontSize -WidthMm $LabelWidthMm -HeightMm $LabelHeightMm -MediaGapMm $GapMm -InsetMm $MarginMm -Xmm $OffsetXmm -Ymm $OffsetYmm -HAlign $HorizontalAlign -VAlign $VerticalAlign -DisableWrap $NoWrap -CopyCount $Copies
    Write-Host "Sent to printer."
    exit 0
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "Label editor"
$form.Width = 1040
$form.Height = 610
$form.StartPosition = "CenterScreen"
$form.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi

$textBox = New-Object System.Windows.Forms.TextBox
$textBox.Left = 16
$textBox.Top = 16
$textBox.Width = 455
$textBox.Height = 130
$textBox.Multiline = $true
$textBox.ScrollBars = "Vertical"
$textBox.WordWrap = $false
$textBox.Text = $Text
$textBox.Font = New-Object System.Drawing.Font($FontFamily, 14, [System.Drawing.FontStyle]::Bold)

$preview = New-Object System.Windows.Forms.Panel
$preview.Left = 500
$preview.Top = 16
$preview.Width = 500
$preview.Height = 390
$preview.BackColor = [System.Drawing.Color]::FromArgb(245, 246, 248)

$printerBox = New-Object System.Windows.Forms.ComboBox
$printerBox.Left = 16
$printerBox.Top = 184
$printerBox.Width = 360
$printerBox.DropDownStyle = "DropDownList"
Get-Printer | ForEach-Object { [void]$printerBox.Items.Add($_.Name) }
$printerBox.SelectedItem = $PrinterName
if ($printerBox.SelectedIndex -lt 0 -and $printerBox.Items.Count -gt 0) {
    $printerBox.SelectedIndex = 0
}

$fontBox = New-Object System.Windows.Forms.TextBox
$fontBox.Left = 16
$fontBox.Top = 224
$fontBox.Width = 360
$fontBox.Text = $FontFamily
$fontBox.Dispose()

$fontBox = New-Object System.Windows.Forms.ComboBox
$fontBox.Left = 16
$fontBox.Top = 224
$fontBox.Width = 360
$fontBox.DropDownStyle = "DropDownList"
$installedFonts = New-Object System.Drawing.Text.InstalledFontCollection
$installedFonts.Families | Sort-Object Name | ForEach-Object {
    [void]$fontBox.Items.Add($_.Name)
}
$fontBox.SelectedItem = $FontFamily
if ($fontBox.SelectedIndex -lt 0 -and $fontBox.Items.Count -gt 0) {
    $fontBox.SelectedItem = "Arial"
    if ($fontBox.SelectedIndex -lt 0) {
        $fontBox.SelectedIndex = 0
    }
}

$widthBox = New-Object System.Windows.Forms.NumericUpDown
$widthBox.Left = 16
$widthBox.Top = 286
$widthBox.Width = 88
$widthBox.Minimum = 20
$widthBox.Maximum = 120
$widthBox.DecimalPlaces = 1
$widthBox.Increment = 0.5
$widthBox.Value = [decimal]$LabelWidthMm

$heightBox = New-Object System.Windows.Forms.NumericUpDown
$heightBox.Left = 126
$heightBox.Top = 286
$heightBox.Width = 88
$heightBox.Minimum = 10
$heightBox.Maximum = 80
$heightBox.DecimalPlaces = 1
$heightBox.Increment = 0.5
$heightBox.Value = [decimal]$LabelHeightMm

$gapBox = New-Object System.Windows.Forms.NumericUpDown
$gapBox.Left = 236
$gapBox.Top = 286
$gapBox.Width = 88
$gapBox.Minimum = 0
$gapBox.Maximum = 10
$gapBox.DecimalPlaces = 1
$gapBox.Increment = 0.5
$gapBox.Value = [decimal]$GapMm

$marginBox = New-Object System.Windows.Forms.NumericUpDown
$marginBox.Left = 346
$marginBox.Top = 286
$marginBox.Width = 88
$marginBox.Minimum = 0
$marginBox.Maximum = 20
$marginBox.DecimalPlaces = 1
$marginBox.Increment = 0.5
$marginBox.Value = [decimal]$MarginMm

$offsetXBox = New-Object System.Windows.Forms.NumericUpDown
$offsetXBox.Left = 16
$offsetXBox.Top = 356
$offsetXBox.Width = 88
$offsetXBox.Minimum = -20
$offsetXBox.Maximum = 30
$offsetXBox.DecimalPlaces = 1
$offsetXBox.Increment = 0.5
$offsetXBox.Value = [decimal]$OffsetXmm

$offsetYBox = New-Object System.Windows.Forms.NumericUpDown
$offsetYBox.Left = 126
$offsetYBox.Top = 356
$offsetYBox.Width = 88
$offsetYBox.Minimum = -20
$offsetYBox.Maximum = 30
$offsetYBox.DecimalPlaces = 1
$offsetYBox.Increment = 0.5
$offsetYBox.Value = [decimal]$OffsetYmm

$fontSizeBox = New-Object System.Windows.Forms.NumericUpDown
$fontSizeBox.Left = 236
$fontSizeBox.Top = 356
$fontSizeBox.Width = 88
$fontSizeBox.Minimum = 6
$fontSizeBox.Maximum = 72
$fontSizeBox.Value = $FontSize

$copiesBox = New-Object System.Windows.Forms.NumericUpDown
$copiesBox.Left = 346
$copiesBox.Top = 356
$copiesBox.Width = 88
$copiesBox.Minimum = 1
$copiesBox.Maximum = 99
$copiesBox.Value = $Copies

$noWrapBox = New-Object System.Windows.Forms.CheckBox
$noWrapBox.Left = 346
$noWrapBox.Top = 408
$noWrapBox.Width = 110
$noWrapBox.Height = 22
$noWrapBox.Text = "No wrap"
$noWrapBox.Checked = [bool]$NoWrap

$hAlignBox = New-Object System.Windows.Forms.ComboBox
$hAlignBox.Left = 16
$hAlignBox.Top = 434
$hAlignBox.Width = 190
$hAlignBox.DropDownStyle = "DropDownList"
[void]$hAlignBox.Items.Add("Left")
[void]$hAlignBox.Items.Add("Center")
[void]$hAlignBox.Items.Add("Right")
$hAlignBox.SelectedItem = $HorizontalAlign
if ($hAlignBox.SelectedIndex -lt 0) { $hAlignBox.SelectedItem = "Center" }

$vAlignBox = New-Object System.Windows.Forms.ComboBox
$vAlignBox.Left = 236
$vAlignBox.Top = 434
$vAlignBox.Width = 190
$vAlignBox.DropDownStyle = "DropDownList"
[void]$vAlignBox.Items.Add("Top")
[void]$vAlignBox.Items.Add("Middle")
[void]$vAlignBox.Items.Add("Bottom")
$vAlignBox.SelectedItem = $VerticalAlign
if ($vAlignBox.SelectedIndex -lt 0) { $vAlignBox.SelectedItem = "Middle" }

$script:loadedImage = $null
$script:loadedImagePath = ""

$imageButton = New-Object System.Windows.Forms.Button
$imageButton.Text = "Load image"
$imageButton.Left = 16
$imageButton.Top = 482
$imageButton.Width = 100
$imageButton.Height = 34

$clearImageButton = New-Object System.Windows.Forms.Button
$clearImageButton.Text = "Clear image"
$clearImageButton.Left = 126
$clearImageButton.Top = 482
$clearImageButton.Width = 100
$clearImageButton.Height = 34

$imageScaleBox = New-Object System.Windows.Forms.NumericUpDown
$imageScaleBox.Left = 236
$imageScaleBox.Top = 482
$imageScaleBox.Width = 88
$imageScaleBox.Minimum = 5
$imageScaleBox.Maximum = 100
$imageScaleBox.Value = 100

$imageHAlignBox = New-Object System.Windows.Forms.ComboBox
$imageHAlignBox.Left = 16
$imageHAlignBox.Top = 542
$imageHAlignBox.Width = 190
$imageHAlignBox.DropDownStyle = "DropDownList"
[void]$imageHAlignBox.Items.Add("Left")
[void]$imageHAlignBox.Items.Add("Center")
[void]$imageHAlignBox.Items.Add("Right")
$imageHAlignBox.SelectedItem = "Center"

$imageVAlignBox = New-Object System.Windows.Forms.ComboBox
$imageVAlignBox.Left = 236
$imageVAlignBox.Top = 542
$imageVAlignBox.Width = 190
$imageVAlignBox.DropDownStyle = "DropDownList"
[void]$imageVAlignBox.Items.Add("Top")
[void]$imageVAlignBox.Items.Add("Middle")
[void]$imageVAlignBox.Items.Add("Bottom")
$imageVAlignBox.SelectedItem = "Middle"

$imageStatusLabel = New-Object System.Windows.Forms.Label
$imageStatusLabel.Left = 346
$imageStatusLabel.Top = 486
$imageStatusLabel.Width = 130
$imageStatusLabel.Height = 48
$imageStatusLabel.AutoEllipsis = $true
$imageStatusLabel.Text = "No image"

$captionLabels = New-Object System.Collections.ArrayList

function Add-Caption([string]$caption, [int]$left, [int]$top) {
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $caption
    $label.Left = $left
    $label.Top = $top
    $label.Width = 105
    $label.Height = 22
    $label.BackColor = $form.BackColor
    $label.AutoEllipsis = $true
    $form.Controls.Add($label)
    [void]$captionLabels.Add($label)
}

Add-Caption "Printer" 16 164
Add-Caption "Font" 16 204
Add-Caption "Width, mm" 16 260
Add-Caption "Height, mm" 126 260
Add-Caption "Gap, mm" 236 260
Add-Caption "Margin, mm" 346 260
Add-Caption "X offset" 16 330
Add-Caption "Y offset" 126 330
Add-Caption "Font size" 236 330
Add-Caption "Copies" 346 330
Add-Caption "Horizontal" 16 408
Add-Caption "Vertical" 236 408
Add-Caption "Image scale" 236 460
Add-Caption "Image horizontal" 16 520
Add-Caption "Image vertical" 236 520

function Update-Preview {
    $preview.Invalidate()
}

$preview.Add_Paint({
    param($sender, $e)

    Draw-PrinterBitmapPreview `
        -Graphics $e.Graphics `
        -PreviewHost $preview `
        -LabelText $textBox.Text `
        -LabelImage $script:loadedImage `
        -ImageScalePercent ([int]$imageScaleBox.Value) `
        -ImageHAlign ([string]$imageHAlignBox.SelectedItem) `
        -ImageVAlign ([string]$imageVAlignBox.SelectedItem) `
        -Family $fontBox.Text `
        -Size ([int]$fontSizeBox.Value) `
        -WidthMm ([double]$widthBox.Value) `
        -HeightMm ([double]$heightBox.Value) `
        -InsetMm ([double]$marginBox.Value) `
        -Xmm ([double]$offsetXBox.Value) `
        -Ymm ([double]$offsetYBox.Value) `
        -HAlign ([string]$hAlignBox.SelectedItem) `
        -VAlign ([string]$vAlignBox.SelectedItem) `
        -DisableWrap ([bool]$noWrapBox.Checked)
})

$controlsForPreview = @($textBox, $fontBox, $widthBox, $heightBox, $marginBox, $offsetXBox, $offsetYBox, $fontSizeBox, $hAlignBox, $vAlignBox, $imageScaleBox, $imageHAlignBox, $imageVAlignBox)
foreach ($control in $controlsForPreview) {
    $control.Add_TextChanged({ Update-Preview })
    if ($control -is [System.Windows.Forms.NumericUpDown]) {
        $control.Add_ValueChanged({ Update-Preview })
    }
    if ($control -is [System.Windows.Forms.ComboBox]) {
        $control.Add_SelectedIndexChanged({ Update-Preview })
    }
}
$noWrapBox.Add_CheckedChanged({ Update-Preview })

$imageButton.Add_Click({
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = "Select image"
    $dialog.Filter = "Images|*.png;*.jpg;*.jpeg;*.bmp;*.gif;*.tif;*.tiff|All files|*.*"
    try {
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $newImage = New-EditorImageCopy -Path $dialog.FileName
            if ($script:loadedImage -ne $null) {
                $script:loadedImage.Dispose()
            }
            $script:loadedImage = $newImage
            $script:loadedImagePath = $dialog.FileName
            $imageStatusLabel.Text = [System.IO.Path]::GetFileName($dialog.FileName)
            Update-Preview
        }
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Image error") | Out-Null
    }
    finally {
        $dialog.Dispose()
    }
})

$clearImageButton.Add_Click({
    if ($script:loadedImage -ne $null) {
        $script:loadedImage.Dispose()
        $script:loadedImage = $null
    }
    $script:loadedImagePath = ""
    $imageStatusLabel.Text = "No image"
    Update-Preview
})

$printButton = New-Object System.Windows.Forms.Button
$printButton.Text = "Print"
$printButton.Left = 500
$printButton.Top = 430
$printButton.Width = 100
$printButton.Height = 34
$printButton.Add_Click({
    try {
        Invoke-LabelPrint `
            -LabelText $textBox.Text `
            -LabelImage $script:loadedImage `
            -ImageScalePercent ([int]$imageScaleBox.Value) `
            -ImageHAlign ([string]$imageHAlignBox.SelectedItem) `
            -ImageVAlign ([string]$imageVAlignBox.SelectedItem) `
            -TargetPrinter ([string]$printerBox.SelectedItem) `
            -Family $fontBox.Text `
            -Size ([int]$fontSizeBox.Value) `
            -WidthMm ([double]$widthBox.Value) `
            -HeightMm ([double]$heightBox.Value) `
            -MediaGapMm ([double]$gapBox.Value) `
            -InsetMm ([double]$marginBox.Value) `
            -Xmm ([double]$offsetXBox.Value) `
            -Ymm ([double]$offsetYBox.Value) `
            -HAlign ([string]$hAlignBox.SelectedItem) `
            -VAlign ([string]$vAlignBox.SelectedItem) `
            -DisableWrap ([bool]$noWrapBox.Checked) `
            -CopyCount ([int]$copiesBox.Value)
        [System.Windows.Forms.MessageBox]::Show("Label sent to printer.", "Done") | Out-Null
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Print error") | Out-Null
    }
})

$homeButton = New-Object System.Windows.Forms.Button
$homeButton.Text = "Home"
$homeButton.Left = 616
$homeButton.Top = 430
$homeButton.Width = 100
$homeButton.Height = 34
$homeButton.Add_Click({
    try {
        Send-LabelHome -TargetPrinter ([string]$printerBox.SelectedItem) -WidthMm ([double]$widthBox.Value) -HeightMm ([double]$heightBox.Value) -MediaGapMm ([double]$gapBox.Value)
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Command error") | Out-Null
    }
})

$feedButton = New-Object System.Windows.Forms.Button
$feedButton.Text = "Feed label"
$feedButton.Left = 732
$feedButton.Top = 430
$feedButton.Width = 100
$feedButton.Height = 34
$feedButton.Add_Click({
    try {
        Send-LabelFeed -TargetPrinter ([string]$printerBox.SelectedItem) -WidthMm ([double]$widthBox.Value) -HeightMm ([double]$heightBox.Value) -MediaGapMm ([double]$gapBox.Value)
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Command error") | Out-Null
    }
})

$calibrateButton = New-Object System.Windows.Forms.Button
$calibrateButton.Text = "Calibrate"
$calibrateButton.Left = 848
$calibrateButton.Top = 430
$calibrateButton.Width = 100
$calibrateButton.Height = 34
$calibrateButton.Add_Click({
    try {
        Send-LabelCalibration -TargetPrinter ([string]$printerBox.SelectedItem) -WidthMm ([double]$widthBox.Value) -HeightMm ([double]$heightBox.Value) -MediaGapMm ([double]$gapBox.Value)
        [System.Windows.Forms.MessageBox]::Show("Calibration command sent. The printer may feed a few labels.", "Done") | Out-Null
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Command error") | Out-Null
    }
})

$presetButton = New-Object System.Windows.Forms.Button
$presetButton.Text = "IPA preset"
$presetButton.Left = 500
$presetButton.Top = 482
$presetButton.Width = 100
$presetButton.Height = 34
$presetButton.Add_Click({
    $line1 = -join ([char[]](1043,1056,1071,1047,1053,1067,1049,32,1048,1047,1054,1055,1056,1054,1055,1048,1051,32,57,57,37))
    $line2 = -join ([char[]](1044,1051,1071,32,1055,1056,1054,1052,1067,1042,1050,1048))
    $line3 = -join ([char[]](1052,1054,1044,1045,1051,1045,1049,32,1055,1054,1057,1051,1045))
    $line4 = -join ([char[]](1060,1054,1058,1054,1055,1054,1051,1048,1052,1045,1056,1053,1054,1049,32,1055,1045,1063,1040,1058,1048))
    $textBox.Text = "$line1`r`n$line2`r`n$line3`r`n$line4"
    $fontSizeBox.Value = 10
    $widthBox.Value = 57
    $heightBox.Value = 39
    $gapBox.Value = 3
    $offsetXBox.Value = 0
    $offsetYBox.Value = 0
    $marginBox.Value = 4
    $noWrapBox.Checked = $false
    $hAlignBox.SelectedItem = "Center"
    $vAlignBox.SelectedItem = "Middle"
})

$note = New-Object System.Windows.Forms.Label
$note.Left = 616
$note.Top = 482
$note.Width = 380
$note.Height = 55
$note.Text = "Print uses direct TSPL bitmap, not Windows page layout. Use Calibrate after changing label roll."

$form.Controls.AddRange(@(
    $textBox, $preview, $printerBox, $fontBox,
    $widthBox, $heightBox, $gapBox, $marginBox,
    $offsetXBox, $offsetYBox, $fontSizeBox, $copiesBox,
    $hAlignBox, $vAlignBox, $noWrapBox,
    $imageButton, $clearImageButton, $imageScaleBox,
    $imageHAlignBox, $imageVAlignBox, $imageStatusLabel,
    $printButton, $homeButton, $feedButton, $calibrateButton,
    $presetButton, $note
))

$form.Add_FormClosing({
    if ($script:loadedImage -ne $null) {
        $script:loadedImage.Dispose()
        $script:loadedImage = $null
    }
})

foreach ($captionLabel in $captionLabels) {
    $captionLabel.BringToFront()
}

Update-Preview
[void]$form.ShowDialog()
