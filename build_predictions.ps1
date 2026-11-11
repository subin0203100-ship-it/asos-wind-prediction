$dataset = 'C:\Users\subin\OneDrive\Desktop\20261111\wind_dataset.csv'
$output = 'C:\Users\subin\OneDrive\Desktop\20261111\predictions.csv'

$rows = @(Import-Csv -LiteralPath $dataset | Sort-Object {
    [datetime]::ParseExact($_.target_time, 'yyyy-MM-dd HH:mm:ss',
        [Globalization.CultureInfo]::InvariantCulture)
})
$train = New-Object 'System.Collections.Generic.List[object]'
$eval = New-Object 'System.Collections.Generic.List[object]'

foreach ($row in $rows) {
    $targetTime = [datetime]::ParseExact(
        $row.target_time, 'yyyy-MM-dd HH:mm:ss',
        [Globalization.CultureInfo]::InvariantCulture)
    if ($targetTime -ge [datetime]'2023-01-01 00:00:00' -and
        $targetTime -lt [datetime]'2024-12-01 00:00:00') {
        [void]$train.Add($row)
    }
    elseif ($targetTime -ge [datetime]'2024-12-01 00:00:00' -and
            $targetTime -lt [datetime]'2025-01-01 00:00:00') {
        [void]$eval.Add($row)
    }
}

$size = 6
$matrix = @()
for ($i = 0; $i -lt $size; $i++) {
    $matrix += ,(New-Object 'double[]' $size)
}
$rhs = New-Object 'double[]' $size

foreach ($row in $train) {
    $features = [double[]]@(
        1,
        [double]$row.current_wind_speed_ms,
        [double]$row.wind_speed_1h_before_ms,
        [double]$row.wind_speed_2h_before_ms,
        [double]$row.current_temperature_C,
        [double]$row.current_humidity_pct
    )
    $actual = [double]$row.target_wind_speed_ms
    for ($i = 0; $i -lt $size; $i++) {
        for ($j = 0; $j -lt $size; $j++) {
            $matrix[$i][$j] += $features[$i] * $features[$j]
        }
        $rhs[$i] += $features[$i] * $actual
    }
}

for ($pivotIndex = 0; $pivotIndex -lt $size; $pivotIndex++) {
    $pivot = $pivotIndex
    for ($i = $pivotIndex + 1; $i -lt $size; $i++) {
        if ([math]::Abs($matrix[$i][$pivotIndex]) -gt
            [math]::Abs($matrix[$pivot][$pivotIndex])) {
            $pivot = $i
        }
    }
    if ([math]::Abs($matrix[$pivot][$pivotIndex]) -lt 1e-12) {
        throw 'Singular regression matrix'
    }
    if ($pivot -ne $pivotIndex) {
        $tempRow = $matrix[$pivotIndex]
        $matrix[$pivotIndex] = $matrix[$pivot]
        $matrix[$pivot] = $tempRow
        $tempValue = $rhs[$pivotIndex]
        $rhs[$pivotIndex] = $rhs[$pivot]
        $rhs[$pivot] = $tempValue
    }
    for ($i = $pivotIndex + 1; $i -lt $size; $i++) {
        $factor = $matrix[$i][$pivotIndex] / $matrix[$pivotIndex][$pivotIndex]
        for ($j = $pivotIndex; $j -lt $size; $j++) {
            $matrix[$i][$j] -= $factor * $matrix[$pivotIndex][$j]
        }
        $rhs[$i] -= $factor * $rhs[$pivotIndex]
    }
}

$coefficients = New-Object 'double[]' $size
for ($i = $size - 1; $i -ge 0; $i--) {
    $sum = $rhs[$i]
    for ($j = $i + 1; $j -lt $size; $j++) {
        $sum -= $matrix[$i][$j] * $coefficients[$j]
    }
    $coefficients[$i] = $sum / $matrix[$i][$i]
}

$predictions = New-Object 'System.Collections.Generic.List[object]'
$baselineError = 0.0
$regressionError = 0.0
foreach ($row in $eval) {
    $features = [double[]]@(
        1,
        [double]$row.current_wind_speed_ms,
        [double]$row.wind_speed_1h_before_ms,
        [double]$row.wind_speed_2h_before_ms,
        [double]$row.current_temperature_C,
        [double]$row.current_humidity_pct
    )
    $prediction = 0.0
    for ($i = 0; $i -lt $size; $i++) {
        $prediction += $coefficients[$i] * $features[$i]
    }
    if ($prediction -lt 0) {
        $prediction = 0
    }
    $actual = [double]$row.target_wind_speed_ms
    $baseline = [double]$row.current_wind_speed_ms
    $baselineError += [math]::Abs($baseline - $actual)
    $regressionError += [math]::Abs($prediction - $actual)
    [void]$predictions.Add([pscustomobject]@{
        prediction_time = $row.prediction_time
        target_time = $row.target_time
        actual_wind_speed_ms = $row.target_wind_speed_ms
        baseline_current_wind_speed_ms = $row.current_wind_speed_ms
        linear_regression_prediction_ms = [math]::Round($prediction, 10)
    })
}

$predictions | Export-Csv -LiteralPath $output -NoTypeInformation -Encoding UTF8
Write-Output "TRAIN_ROWS=$($train.Count)"
Write-Output "EVAL_ROWS=$($eval.Count)"
Write-Output "BASELINE_MAE=$([math]::Round($baselineError / $eval.Count, 10))"
Write-Output "LINEAR_REGRESSION_MAE=$([math]::Round($regressionError / $eval.Count, 10))"
Write-Output "OUTPUT=$output"
Write-Output 'FIRST_EVALUATION_ROW:'
$predictions | Select-Object -First 1 | Format-List
