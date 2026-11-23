param(
  [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
  [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $OutputPath = Join-Path $ProjectRoot "Docs\RV32I_UVM_Tables.pptx"
}

$tableRoot = Join-Path $ProjectRoot "Docs\PPT_Materials\Tables"
$orderedTables = @(
  @{ File = "03_verification_scope.tsv"; Title = "검증 대상 및 목표"; Widths = @(0.23, 0.77) },
  @{ File = "05_interface.tsv"; Title = "인터페이스"; Widths = @(0.18, 0.35, 0.47) },
  @{ File = "05_sva.tsv"; Title = "SVA 상세 — Assertion과 Reachability"; Widths = @(0.16, 0.31, 0.24, 0.29) },
  @{ File = "06_probe_timing.tsv"; Title = "Core / Probe Timing"; Widths = @(0.19, 0.35, 0.46) },
  @{ File = "08_items.tsv"; Title = "Sequence와 Item — Item"; Widths = @(0.22, 0.36, 0.42) },
  @{ File = "08_sequences.tsv"; Title = "Sequence와 Item — Sequence"; Widths = @(0.18, 0.37, 0.45) },
  @{ File = "09_monitor.tsv"; Title = "Monitor와 Commit Sampling"; Widths = @(0.18, 0.37, 0.45) },
  @{ File = "10_scoreboard.tsv"; Title = "Scoreboard"; Widths = @(0.17, 0.39, 0.44) },
  @{ File = "11_coverage_summary.tsv"; Title = "Coverage 요약"; Widths = @(0.22, 0.48, 0.30) },
  @{ File = "11_coverage.tsv"; Title = "Coverage"; Widths = @(0.20, 0.41, 0.39) },
  @{ File = "12_clean_results.tsv"; Title = "Regression 결과 — Directed / Random"; Widths = @(0.28, 0.38, 0.34) },
  @{ File = "12_xprop_results.tsv"; Title = "Regression 결과 — XPROP"; Widths = @(0.28, 0.42, 0.30) },
  @{ File = "12_illegal_results.tsv"; Title = "Regression 결과 — Illegal Negative"; Widths = @(0.28, 0.42, 0.30) }
)

function Get-Rgb([int]$Red, [int]$Green, [int]$Blue) {
  return $Red + (256 * $Green) + (65536 * $Blue)
}

function Set-TextStyle($Shape, [string]$FontName, [double]$FontSize,
                       [int]$Color, [bool]$Bold, [int]$Alignment) {
  $range = $Shape.TextFrame.TextRange
  $range.Font.Name = $FontName
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

function Add-TitleBand($Slide, [string]$Title, [int]$SlideNumber,
                       [string]$SourceName) {
  $titleShape = $Slide.Shapes.AddTextbox(1, 52, 24, 850, 54)
  $titleShape.TextFrame.TextRange.Text = $Title
  Set-TextStyle $titleShape "맑은 고딕" 28 (Get-Rgb 20 20 20) $true 1

  $line = $Slide.Shapes.AddShape(1, 45, 88, 870, 3)
  $line.Fill.ForeColor.RGB = Get-Rgb 47 117 181
  $line.Line.Visible = 0

  $number = $Slide.Shapes.AddTextbox(1, 46, 510, 100, 18)
  $number.TextFrame.TextRange.Text = ("{0:D2}" -f $SlideNumber)
  Set-TextStyle $number "맑은 고딕" 9 (Get-Rgb 110 118 130) $false 1

  $source = $Slide.Shapes.AddTextbox(1, 560, 508, 355, 20)
  $source.TextFrame.TextRange.Text = $SourceName
  Set-TextStyle $source "맑은 고딕" 8.5 (Get-Rgb 110 118 130) $false 3
}

function Get-BodyFontSize([int]$RowCount, [int]$ColumnCount) {
  if ($RowCount -ge 13) { return 11.5 }
  if ($RowCount -ge 11) { return 12.5 }
  if ($RowCount -ge 9)  { return 13.5 }
  if ($ColumnCount -eq 2) { return 15.0 }
  return 14.5
}

function Get-RowHeight([int]$RowCount) {
  if ($RowCount -ge 13) { return 29.5 }
  if ($RowCount -ge 11) { return 33.0 }
  if ($RowCount -ge 9)  { return 37.0 }
  if ($RowCount -ge 7)  { return 42.0 }
  return 48.0
}

$powerPoint = $null
$presentation = $null

try {
  $powerPoint = New-Object -ComObject PowerPoint.Application
  $presentation = $powerPoint.Presentations.Add()
  $presentation.PageSetup.SlideWidth = 960
  $presentation.PageSetup.SlideHeight = 540

  # Cover slide
  $cover = $presentation.Slides.Add(1, 12)
  $cover.FollowMasterBackground = 0
  $cover.Background.Fill.ForeColor.RGB = Get-Rgb 255 255 255

  $accent = $cover.Shapes.AddShape(1, 0, 0, 18, 540)
  $accent.Fill.ForeColor.RGB = Get-Rgb 47 117 181
  $accent.Line.Visible = 0

  $coverTitle = $cover.Shapes.AddTextbox(1, 78, 145, 800, 78)
  $coverTitle.TextFrame.TextRange.Text = "RV32I UVM Verification"
  Set-TextStyle $coverTitle "맑은 고딕" 38 (Get-Rgb 20 20 20) $true 1

  $coverSub = $cover.Shapes.AddTextbox(1, 82, 235, 720, 52)
  $coverSub.TextFrame.TextRange.Text = "TSV 기반 검증 표 모음"
  Set-TextStyle $coverSub "맑은 고딕" 23 (Get-Rgb 47 117 181) $true 1

  $coverMeta = $cover.Shapes.AddTextbox(1, 82, 315, 720, 70)
  $coverMeta.TextFrame.TextRange.Text = "Legal RV32I R-type / I-type`rDirected · Random 20-seed · XPROP · Illegal Negative"
  Set-TextStyle $coverMeta "맑은 고딕" 15 (Get-Rgb 70 78 90) $false 1

  $coverFooter = $cover.Shapes.AddTextbox(1, 82, 470, 720, 24)
  $coverFooter.TextFrame.TextRange.Text = "2026.09.13"
  Set-TextStyle $coverFooter "맑은 고딕" 11 (Get-Rgb 110 118 130) $false 1

  $slideIndex = 2
  foreach ($spec in $orderedTables) {
    $tsvPath = Join-Path $tableRoot $spec.File
    if (-not (Test-Path -LiteralPath $tsvPath)) {
      throw "Missing TSV: $tsvPath"
    }

    $rows = @(Get-Content -LiteralPath $tsvPath -Encoding UTF8 | ForEach-Object {
      ,($_ -split "`t", -1)
    })
    if ($rows.Count -eq 0) { continue }

    $columnCount = $rows[0].Count
    foreach ($row in $rows) {
      if ($row.Count -ne $columnCount) {
        throw "Column mismatch in $($spec.File)"
      }
    }

    $slide = $presentation.Slides.Add($slideIndex, 12)
    $slide.FollowMasterBackground = 0
    $slide.Background.Fill.ForeColor.RGB = Get-Rgb 255 255 255
    Add-TitleBand $slide $spec.Title $slideIndex $spec.File

    $bodyRowHeight = Get-RowHeight $rows.Count
    $headerHeight = 32.0
    $tableHeight = $headerHeight + (($rows.Count - 1) * $bodyRowHeight)
    if ($tableHeight -gt 397) { $tableHeight = 397 }

    $tableShape = $slide.Shapes.AddTable($rows.Count, $columnCount,
                                         45, 108, 870, $tableHeight)
    $table = $tableShape.Table

    for ($column = 1; $column -le $columnCount; $column++) {
      $table.Columns.Item($column).Width = 870 * $spec.Widths[$column - 1]
    }

    $table.Rows.Item(1).Height = $headerHeight
    for ($row = 2; $row -le $rows.Count; $row++) {
      $table.Rows.Item($row).Height = $bodyRowHeight
    }

    $bodyFontSize = Get-BodyFontSize $rows.Count $columnCount
    for ($row = 1; $row -le $rows.Count; $row++) {
      for ($column = 1; $column -le $columnCount; $column++) {
        $cell = $table.Cell($row, $column)
        $cell.Shape.TextFrame.TextRange.Text = [string]$rows[$row - 1][$column - 1]

        foreach ($borderIndex in 1..4) {
          $cell.Borders.Item($borderIndex).ForeColor.RGB = Get-Rgb 35 40 47
          $cell.Borders.Item($borderIndex).Weight = 1.1
        }

        if ($row -eq 1) {
          $cell.Shape.Fill.ForeColor.RGB = Get-Rgb 91 155 213
          Set-TextStyle $cell.Shape "맑은 고딕" 14.5 (Get-Rgb 255 255 255) $true 2
        }
        else {
          if (($row % 2) -eq 0) {
            $cell.Shape.Fill.ForeColor.RGB = Get-Rgb 255 255 255
          }
          else {
            $cell.Shape.Fill.ForeColor.RGB = Get-Rgb 247 250 252
          }
          $alignment = if (($spec.File -like "12_*") -and ($column -eq 3)) { 2 } else { 1 }
          Set-TextStyle $cell.Shape "맑은 고딕" $bodyFontSize (Get-Rgb 25 31 42) $false $alignment
        }
      }
    }

    $slideIndex++
  }

  $outputDirectory = Split-Path -Parent $OutputPath
  if (-not (Test-Path -LiteralPath $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory | Out-Null
  }

  $presentation.SaveAs($OutputPath, 24)
  Write-Output ("Created: {0}" -f $OutputPath)
  Write-Output ("Slides: {0}" -f $presentation.Slides.Count)
}
finally {
  if ($presentation) {
    $presentation.Close()
    [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($presentation)
  }
  if ($powerPoint) {
    $powerPoint.Quit()
    [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($powerPoint)
  }
  [GC]::Collect()
  [GC]::WaitForPendingFinalizers()
}

