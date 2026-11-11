$input = 'C:\Users\subin\OneDrive\Desktop\20261111\predictions.csv'
$output = 'C:\Users\subin\OneDrive\Desktop\20261111\prediction_week.png'
$rows = @(Import-Csv -LiteralPath $input | ForEach-Object {
    $target = [datetime]::ParseExact(
        $_.target_time, 'yyyy-MM-dd HH:mm:ss',
        [Globalization.CultureInfo]::InvariantCulture)
    [pscustomobject]@{
        Target = $target
        Actual = [double]$_.actual_wind_speed_ms
        Baseline = [double]$_.baseline_current_wind_speed_ms
        Regression = [double]$_.linear_regression_prediction_ms
    }
} | Sort-Object Target)

$december = @($rows | Where-Object {
    $_.Target -ge [datetime]'2024-12-01 00:00:00' -and
    $_.Target -lt [datetime]'2025-01-01 00:00:00'
})
$week = @($december | Where-Object {
    $_.Target -le [datetime]'2024-12-07 23:00:00'
})

$baselineError = ($december | ForEach-Object {
    [math]::Abs($_.Baseline - $_.Actual)
} | Measure-Object -Average).Average
$regressionError = ($december | ForEach-Object {
    [math]::Abs($_.Regression - $_.Actual)
} | Measure-Object -Average).Average

Add-Type -AssemblyName System.Drawing
$width = 1800
$height = 900
$left = 100
$right = 80
$top = 70
$bottom = 115
$plotWidth = $width - $left - $right
$plotHeight = $height - $top - $bottom
$maxValue = [math]::Ceiling((@($week | ForEach-Object {
    @($_.Actual, $_.Baseline, $_.Regression)
} | Measure-Object -Maximum).Maximum) + 1)

$bitmap = New-Object System.Drawing.Bitmap($width, $height)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
$graphics.Clear([Drawing.Color]::White)
$font = New-Object Drawing.Font('Arial', 12)
$smallFont = New-Object Drawing.Font('Arial', 10)
$axisPen = New-Object Drawing.Pen([Drawing.Color]::Black, 1)
$gridPen = New-Object Drawing.Pen([Drawing.Color]::LightGray, 1)
$actualPen = New-Object Drawing.Pen([Drawing.Color]::Black, 2)
$baselinePen = New-Object Drawing.Pen([Drawing.Color]::Gray, 2)
$baselinePen.DashStyle = [Drawing.Drawing2D.DashStyle]::Dash
$regressionPen = New-Object Drawing.Pen([Drawing.Color]::Blue, 2)
$brush = [Drawing.Brushes]::Black

for ($tick = 0; $tick -le $maxValue; $tick++) {
    $y = $top + $plotHeight - ($tick / $maxValue * $plotHeight)
    $graphics.DrawLine($gridPen, $left, $y, $left + $plotWidth, $y)
    $graphics.DrawString("$tick", $font, $brush, 58, $y - 9)
}
$graphics.DrawLine($axisPen, $left, $top, $left, $top + $plotHeight)
$graphics.DrawLine($axisPen, $left, $top + $plotHeight, $left + $plotWidth, $top + $plotHeight)

function Get-X([int]$index, [int]$count) {
    if ($count -le 1) { return $left }
    return $left + ($index / ($count - 1) * $plotWidth)
}
function Get-Y([double]$value) {
    return $top + $plotHeight - ($value / $maxValue * $plotHeight)
}
function Draw-Series($values, $pen) {
    for ($i = 1; $i -lt $values.Count; $i++) {
        $graphics.DrawLine(
            $pen,
            (Get-X ($i - 1) $values.Count), (Get-Y $values[$i-1]),
            (Get-X $i $values.Count), (Get-Y $values[$i])
        )
    }
}

Draw-Series @($week | ForEach-Object { $_.Actual }) $actualPen
Draw-Series @($week | ForEach-Object { $_.Baseline }) $baselinePen
Draw-Series @($week | ForEach-Object { $_.Regression }) $regressionPen

for ($i = 0; $i -lt $week.Count; $i += 12) {
    $x = Get-X $i $week.Count
    $graphics.DrawLine($axisPen, $x, $top + $plotHeight, $x, $top + $plotHeight + 6)
    $label = $week[$i].Target.ToString('MM-dd HH:mm')
    $graphics.DrawString($label, $smallFont, $brush, $x - 30, $top + $plotHeight + 10)
}

$graphics.DrawString('Wind speed prediction: 2024-12-01 to 2024-12-07 (KST)', $font, $brush, 520, 20)
$graphics.DrawString('Target time (KST)', $font, $brush, 810, $height - 45)
$graphics.TranslateTransform(25, 490)
$graphics.RotateTransform(-90)
$graphics.DrawString('Wind speed (m/s)', $font, $brush, 0, 0)
$graphics.ResetTransform()

$legendX = $width - 400
$legendY = 35
$graphics.DrawLine($actualPen, $legendX, $legendY + 8, $legendX + 35, $legendY + 8)
$graphics.DrawString('Actual', $font, $brush, $legendX + 45, $legendY)
$graphics.DrawLine($baselinePen, $legendX + 150, $legendY + 8, $legendX + 185, $legendY + 8)
$graphics.DrawString('Baseline', $font, $brush, $legendX + 195, $legendY)
$graphics.DrawLine($regressionPen, $legendX + 305, $legendY + 8, $legendX + 340, $legendY + 8)
$graphics.DrawString('Linear regression', $font, $brush, $legendX + 350, $legendY)

$bitmap.Save($output, [Drawing.Imaging.ImageFormat]::Png)
$graphics.Dispose()
$bitmap.Dispose()
$font.Dispose()
$smallFont.Dispose()
$axisPen.Dispose()
$gridPen.Dispose()
$actualPen.Dispose()
$baselinePen.Dispose()
$regressionPen.Dispose()

Write-Output "WEEK_ROWS=$($week.Count)"
Write-Output "DECEMBER_ROWS=$($december.Count)"
Write-Output "BASELINE_MAE=$([math]::Round($baselineError, 10))"
Write-Output "LINEAR_REGRESSION_MAE=$([math]::Round($regressionError, 10))"
Write-Output "OUTPUT=$output"
