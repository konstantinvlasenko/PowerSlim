<#
.SYNOPSIS
  Runs the PowerSlim FitNesse acceptance suites and fails if any page fails.

.DESCRIPTION
  Downloads the pinned FitNesse release (checksum verified) if it is missing, runs each suite
  through the FitNesse command line and prints one line per failing page.
  Exit code is 0 when every page passes, 1 otherwise.

  PowerSlim.SuiteWrongFailedException is not run here: it fails on purpose and is verified
  from PowerSlim.OriginalMode.SuiteCommon.TestScenario.

.PARAMETER Shell
  PowerShell used for the SLIM runner. Remote agents started by the pages use the same executable.
  'pwsh' (PowerShell 7+, default) or 'powershell' (Windows PowerShell 5.1).

.EXAMPLE
  ./tests/Invoke-AcceptanceTests.ps1
  ./tests/Invoke-AcceptanceTests.ps1 -Shell powershell -Suite OriginalMode
#>
[CmdletBinding()]
param(
  [ValidateSet('pwsh', 'powershell')]
  [string]$Shell = 'pwsh',

  [string[]]$Suite = @('OriginalMode', 'SuiteREST'),

  [int]$FitNessePort = 8085
)

$ErrorActionPreference = 'Stop'
$FitNesseVersion = '20260313'
$FitNesseSha256 = '0b45556b2676338abac56fd202c4f0ac4f5ecb3b4019f2a88251e167c3144ed5'

$repo = Split-Path -Parent $PSScriptRoot
$jar = Join-Path $repo 'fitnesse-standalone.jar'
Push-Location $repo
try {
  if (-not (Test-Path $jar) -or (Get-FileHash $jar -Algorithm SHA256).Hash -ne $FitNesseSha256) {
    $url = "https://repo1.maven.org/maven2/org/fitnesse/fitnesse/$FitNesseVersion/fitnesse-$FitNesseVersion-standalone.jar"
    Write-Host "Downloading $url"
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $url -OutFile $jar -UseBasicParsing
    $actual = (Get-FileHash $jar -Algorithm SHA256).Hash
    if ($actual -ne $FitNesseSha256) {
      Remove-Item $jar
      throw "FitNesse checksum mismatch: expected $FitNesseSha256, got $actual"
    }
  }

  # The suites default to pwsh; override the wiki variable for Windows PowerShell 5.1.
  $commandPattern = ''
  if ($Shell -eq 'powershell') {
    $commandPattern = '&COMMAND_PATTERN=' + [uri]::EscapeDataString('powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ./slim.ps1')
  }

  $failed = 0
  foreach ($name in $Suite) {
    $command = "PowerSlim.${name}?suite&format=xml$commandPattern"
    Write-Host "===== $name ($Shell)"
    $output = (& java -jar $jar -o -p $FitNessePort -c $command 2>&1 | ForEach-Object { "$_" }) -join "`n"
    $start = $output.IndexOf([char]60 + '?xml')
    if ($start -lt 0) {
      Write-Host $output
      Write-Host "FAIL $name produced no XML report"
      $failed++
      continue
    }

    $report = [xml]$output.Substring($start)
    foreach ($page in $report.testResults.result) {
      $c = $page.counts
      $status = if ([int]$c.wrong + [int]$c.exceptions -gt 0) { 'FAIL' } else { 'ok  ' }
      Write-Host ("{0} {1}  R:{2} W:{3} I:{4} E:{5}" -f $status, $page.relativePageName, $c.right, $c.wrong, $c.ignores, $c.exceptions)
      if ($status -eq 'FAIL') {
        $failed++
        # Suite reports only carry counts; the stored page result has the rendered tables
        $detail = (& java -jar $jar -o -p $FitNessePort -c "$($page.pageHistoryLink)&format=xml" 2>&1 | ForEach-Object { "$_" }) -join "`n"
        $detailStart = $detail.IndexOf([char]60 + '?xml')
        if ($detailStart -lt 0) { continue }
        $html = [System.Net.WebUtility]::HtmlDecode(([xml]$detail.Substring($detailStart)).testResults.result.content)
        # Failed checks and exceptions are rendered as <span|td class="fail|error">; aborts as __EXCEPTION__ text
        [regex]::Matches($html, '<(span|td)[^>]*class="(?:fail|error)"[^>]*>(?<text>.*?)</\1>|(?<text>__EXCEPTION__[^<]*)', 'Singleline') |
          Where-Object { $_.Groups['text'].Value.Trim() } |
          Select-Object -First 3 |
          ForEach-Object {
            $text = ($_.Groups['text'].Value -replace '<[^>]+>', ' ' -replace '\s+', ' ').Trim()
            Write-Host ('       ' + $text.Substring(0, [Math]::Min(300, $text.Length)))
          }
      }
    }
    $f = $report.testResults.finalCounts
    Write-Host ("----- {0}: {1} pages passed, {2} failed" -f $name, $f.right, ([int]$f.wrong + [int]$f.exceptions))
  }
}
finally {
  # Newer FitNesse writes rerun pages and the test pages leave a few scratch files behind
  Remove-Item -Force -ErrorAction SilentlyContinue (Join-Path $repo 'FitNesseRoot/RerunLastFailures_*.wiki'),
    (Join-Path $repo 'file1.txt'), (Join-Path $repo 'file2.txt'), (Join-Path $repo 'ps-log.txt'), (Join-Path $repo 'ps-error.txt')
  Pop-Location
}

if ($failed) {
  Write-Host "$failed page(s) failed"
  exit 1
}
Write-Host 'All acceptance pages passed'
