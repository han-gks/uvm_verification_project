param(
  [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
  [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $OutputPath = Join-Path $ProjectRoot "Docs\RV32I_UVM_6min.pptx"
}

$tableRoot = Join-Path $ProjectRoot "Docs\PPT_Materials\Tables"

$mainTables = @(
  @{ File="6min\01_scope_summary.tsv"; Title="1. 검증 대상 및 범위"; Widths=@(0.20,0.48,0.32); Time="35초" },
  @{ File="6min\02_interface_probe_summary.tsv"; Title="2. Interface와 Probe 요약"; Widths=@(0.20,0.43,0.37); Time="40초" },
  @{ File="6min\03_stimulus_summary.tsv"; Title="3. 검증 시나리오"; Widths=@(0.27,0.40,0.33); Time="50초" },
  @{ File="6min\04_monitor_scoreboard_summary.tsv"; Title="4. Monitor와 Scoreboard"; Widths=@(0.18,0.43,0.39); Time="55초" },
  @{ File="6min\05_sva_coverage_summary.tsv"; Title="5. SVA와 Coverage 요약"; Widths=@(0.19,0.43,0.38); Time="55초" },
  @{ File="6min\06_regression_summary.tsv"; Title="6. 최종 Regression 결과"; Widths=@(0.22,0.43,0.35); Time="80초" },
  @{ File="6min\07_conclusion_summary.tsv"; Title="7. 결론과 한계"; Widths=@(0.23,0.45,0.32); Time="25초" }
)

$appendixTables = @(
  @{ File="03_verification_scope.tsv"; Title="검증 대상 및 목표"; Widths=@(0.23,0.77) },
  @{ File="05_interface.tsv"; Title="인터페이스"; Widths=@(0.18,0.35,0.47) },
  @{ File="05_sva.tsv"; Title="SVA 상세 — Assertion과 Reachability"; Widths=@(0.16,0.31,0.24,0.29) },
  @{ File="06_probe_timing.tsv"; Title="Core / Probe Timing"; Widths=@(0.19,0.35,0.46) },
  @{ File="08_items.tsv"; Title="Sequence와 Item — Item"; Widths=@(0.22,0.36,0.42) },
  @{ File="08_sequences.tsv"; Title="Sequence와 Item — Sequence"; Widths=@(0.18,0.37,0.45) },
  @{ File="09_monitor.tsv"; Title="Monitor와 Commit Sampling"; Widths=@(0.18,0.37,0.45) },
  @{ File="10_scoreboard.tsv"; Title="Scoreboard"; Widths=@(0.17,0.39,0.44) },
  @{ File="11_coverage_summary.tsv"; Title="Coverage 요약"; Widths=@(0.22,0.48,0.30) },
  @{ File="11_coverage.tsv"; Title="Coverage"; Widths=@(0.20,0.41,0.39) },
  @{ File="12_clean_results.tsv"; Title="Regression 결과 — Directed / Random"; Widths=@(0.28,0.38,0.34) },
  @{ File="12_xprop_results.tsv"; Title="Regression 결과 — XPROP"; Widths=@(0.28,0.42,0.30) },
  @{ File="12_illegal_results.tsv"; Title="Regression 결과 — Illegal Negative"; Widths=@(0.28,0.42,0.30) }
)

function Get-Rgb([int]$Red, [int]$Green, [int]$Blue) {
  return $Red + (256 * $Green) + (65536 * $Blue)
}

function Set-TextStyle($Shape, [double]$FontSize, [int]$Color,
                       [bool]$Bold, [int]$Alignment) {
  $range = $Shape.TextFrame.TextRange
  $range.Font.Name = "맑은 고딕"
  $range.Font.Size = $FontSize
  $range.Font.Color.RGB = $Color
  $range.Font.Bold = if ($Bold) { -1 } else { 0 }
  $range.ParagraphFormat.Alignment = $Alignment
  $Shape.TextFrame.VerticalAnchor = 3
  $Shape.TextFrame.MarginLeft = 7
  $Shape.TextFrame.MarginRight = 7
  $Shape.TextFrame.MarginTop = 3
  $Shape.TextFrame.MarginBottom = 3
}

function Add-Text($Slide, [double]$X, [double]$Y, [double]$W, [double]$H,
                  [string]$Text, [double]$Size, [int]$Color,
                  [bool]$Bold=$false, [int]$Alignment=1) {
  $shape = $Slide.Shapes.AddTextbox(1, $X, $Y, $W, $H)
  $shape.TextFrame.TextRange.Text = $Text
  Set-TextStyle $shape $Size $Color $Bold $Alignment
  return $shape
}

function Add-TitleBand($Slide, [string]$Title, [string]$DisplayNumber,
                       [string]$SourceName, [string]$TimeLabel,
                       [bool]$IsAppendix) {
  $titleSize = if ($IsAppendix) { 21.0 } else { 28.0 }
  $null = Add-Text $Slide 52 24 850 54 $Title $titleSize (Get-Rgb 20 20 20) $true 1

  $line = $Slide.Shapes.AddShape(1, 45, 88, 870, 3)
  $line.Fill.ForeColor.RGB = Get-Rgb 47 117 181
  $line.Line.Visible = 0

  $null = Add-Text $Slide 46 510 120 18 $DisplayNumber 9 (Get-Rgb 110 118 130) $false 1
  if (-not [string]::IsNullOrWhiteSpace($TimeLabel)) {
    $null = Add-Text $Slide 360 508 240 20 ("권장 발표 {0}" -f $TimeLabel) 9.5 (Get-Rgb 110 118 130) $false 2
  }
  $null = Add-Text $Slide 600 508 315 20 $SourceName 8.5 (Get-Rgb 110 118 130) $false 3
}

function Read-TsvRows([string]$RelativePath) {
  $path = Join-Path $tableRoot $RelativePath
  if (-not (Test-Path -LiteralPath $path)) { throw "Missing TSV: $path" }
  return @(Get-Content -LiteralPath $path -Encoding UTF8 | ForEach-Object { ,($_ -split "`t", -1) })
}

function Get-BodyFontSize([int]$RowCount, [int]$ColumnCount, [bool]$IsAppendix) {
  if ($RowCount -ge 13) { return 11.5 }
  if ($RowCount -ge 11) { return 12.5 }
  if ($RowCount -ge 9)  { return 13.5 }
  if ($IsAppendix -and $ColumnCount -eq 2) { return 15.0 }
  if ($ColumnCount -ge 4) { return 13.5 }
  return 14.5
}

function Get-RowHeight([int]$RowCount) {
  if ($RowCount -ge 13) { return 29.5 }
  if ($RowCount -ge 11) { return 33.0 }
  if ($RowCount -ge 9)  { return 37.0 }
  if ($RowCount -ge 7)  { return 42.0 }
  return 48.0
}

function Add-TableSlide($Presentation, [int]$InsertIndex, $Spec,
                        [string]$DisplayNumber, [bool]$IsAppendix) {
  $rows = Read-TsvRows $Spec.File
  if ($rows.Count -eq 0) { return }
  $columnCount = $rows[0].Count
  foreach ($rowData in $rows) {
    if ($rowData.Count -ne $columnCount) { throw "Column mismatch in $($Spec.File)" }
  }

  $slide = $Presentation.Slides.Add($InsertIndex, 12)
  $slide.FollowMasterBackground = 0
  $slide.Background.Fill.ForeColor.RGB = Get-Rgb 255 255 255

  $title = if ($IsAppendix) { "Appendix $DisplayNumber. $($Spec.Title)" } else { $Spec.Title }
  $time = if ($IsAppendix) { "" } else { $Spec.Time }
  $sourceName = Split-Path -Leaf $Spec.File
  Add-TitleBand $slide $title $DisplayNumber $sourceName $time $IsAppendix

  $bodyRowHeight = Get-RowHeight $rows.Count
  $headerHeight = 32.0
  $tableHeight = $headerHeight + (($rows.Count - 1) * $bodyRowHeight)
  if ($tableHeight -gt 397) { $tableHeight = 397 }
  $tableY = 108 + ((397 - $tableHeight) / 2)

  $tableShape = $slide.Shapes.AddTable($rows.Count, $columnCount, 45, $tableY, 870, $tableHeight)
  $table = $tableShape.Table
  for ($column = 1; $column -le $columnCount; $column++) {
    $table.Columns.Item($column).Width = 870 * $Spec.Widths[$column - 1]
  }
  $table.Rows.Item(1).Height = $headerHeight
  for ($rowIndex = 2; $rowIndex -le $rows.Count; $rowIndex++) {
    $table.Rows.Item($rowIndex).Height = $bodyRowHeight
  }

  $fontSize = Get-BodyFontSize $rows.Count $columnCount $IsAppendix
  for ($rowIndex = 1; $rowIndex -le $rows.Count; $rowIndex++) {
    for ($column = 1; $column -le $columnCount; $column++) {
      $cell = $table.Cell($rowIndex, $column)
      $cell.Shape.TextFrame.TextRange.Text = [string]$rows[$rowIndex - 1][$column - 1]
      foreach ($borderIndex in 1..4) {
        $cell.Borders.Item($borderIndex).ForeColor.RGB = Get-Rgb 35 40 47
        $cell.Borders.Item($borderIndex).Weight = 1.1
      }
      if ($rowIndex -eq 1) {
        $cell.Shape.Fill.ForeColor.RGB = Get-Rgb 91 155 213
        Set-TextStyle $cell.Shape 14.5 (Get-Rgb 255 255 255) $true 2
      }
      else {
        $cell.Shape.Fill.ForeColor.RGB = if (($rowIndex % 2) -eq 0) { Get-Rgb 255 255 255 } else { Get-Rgb 247 250 252 }
        $alignment = if (($Spec.File -like "12_*") -and ($column -eq 3)) { 2 } else { 1 }
        Set-TextStyle $cell.Shape $fontSize (Get-Rgb 25 31 42) $false $alignment
      }
    }
  }
}

$powerPoint = $null
$presentation = $null

try {
  $powerPoint = New-Object -ComObject PowerPoint.Application
  $presentation = $powerPoint.Presentations.Add()
  $presentation.PageSetup.SlideWidth = 960
  $presentation.PageSetup.SlideHeight = 540

  $cover = $presentation.Slides.Add(1, 12)
  $cover.FollowMasterBackground = 0
  $cover.Background.Fill.ForeColor.RGB = Get-Rgb 255 255 255
  $accent = $cover.Shapes.AddShape(1, 0, 0, 18, 540)
  $accent.Fill.ForeColor.RGB = Get-Rgb 47 117 181
  $accent.Line.Visible = 0
  $null = Add-Text $cover 78 140 800 78 "RV32I UVM Verification" 38 (Get-Rgb 20 20 20) $true 1
  $null = Add-Text $cover 82 230 720 52 "6분 발표용 표 요약" 23 (Get-Rgb 47 117 181) $true 1
  $null = Add-Text $cover 82 300 760 78 "본문 8장 · 권장 5분 45초`r상세 원본 표 12장은 Appendix 수록" 15 (Get-Rgb 70 78 90) $false 1
  $null = Add-Text $cover 82 470 720 24 "2026.09.13  |  권장 발표 10초" 11 (Get-Rgb 110 118 130) $false 1

  $insertIndex = 2
  $mainNumber = 2
  foreach ($spec in $mainTables) {
    Add-TableSlide $presentation $insertIndex $spec ("{0:D2}" -f $mainNumber) $false
    $insertIndex++
    $mainNumber++
  }

  $divider = $presentation.Slides.Add($insertIndex, 12)
  $divider.FollowMasterBackground = 0
  $divider.Background.Fill.ForeColor.RGB = Get-Rgb 255 255 255
  $dividerAccent = $divider.Shapes.AddShape(1, 0, 0, 18, 540)
  $dividerAccent.Fill.ForeColor.RGB = Get-Rgb 47 117 181
  $dividerAccent.Line.Visible = 0
  $null = Add-Text $divider 78 170 800 70 "Appendix" 40 (Get-Rgb 20 20 20) $true 1
  $null = Add-Text $divider 82 250 760 46 "원본 TSV 상세 표" 24 (Get-Rgb 47 117 181) $true 1
  $null = Add-Text $divider 82 315 760 50 "발표 본문에서 압축한 세부 항목과 근거" 15 (Get-Rgb 70 78 90) $false 1
  $insertIndex++

  $appendixIndex = 1
  foreach ($spec in $appendixTables) {
    Add-TableSlide $presentation $insertIndex $spec ("A{0}" -f $appendixIndex) $true
    $insertIndex++
    $appendixIndex++
  }

  $outputDirectory = Split-Path -Parent $OutputPath
  if (-not (Test-Path -LiteralPath $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory | Out-Null
  }
  $presentation.SaveAs($OutputPath, 24)
  Write-Output ("Created: {0}" -f $OutputPath)
  Write-Output ("Slides: {0} (main 8 + divider 1 + appendix 12)" -f $presentation.Slides.Count)
}
finally {
  if ($presentation) {
    $presentation.Close()
    [void][Runtime.InteropServices.Marshal]::ReleaseComObject($presentation)
  }
  if ($powerPoint) {
    $powerPoint.Quit()
    [void][Runtime.InteropServices.Marshal]::ReleaseComObject($powerPoint)
  }
  [GC]::Collect()
  [GC]::WaitForPendingFinalizers()
}



