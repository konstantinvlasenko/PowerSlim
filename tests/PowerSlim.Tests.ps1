# Unit tests for the SLIM protocol helpers in slim.ps1. Run with: Invoke-Pester ./tests
BeforeAll {
  # slim.ps1 starts a TCP listener when it runs, so load only its function definitions,
  # top-level constants and aliases (via the parser) instead of executing the script.
  $path = Join-Path (Split-Path -Parent $PSScriptRoot) 'slim.ps1'
  $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$null)
  $wanted = $ast.EndBlock.Statements | Where-Object {
    $_ -is [System.Management.Automation.Language.FunctionDefinitionAst] -or
    ($_ -is [System.Management.Automation.Language.AssignmentStatementAst] -and $_.Extent.Text -notmatch 'MyInvocation|TcpListener') -or
    ($_ -is [System.Management.Automation.Language.PipelineAst] -and $_.Extent.Text -match '^new-alias\s')
  }
  . ([scriptblock]::Create(($wanted | ForEach-Object { $_.Extent.Text }) -join "`n"))

  # Build a SLIM list the way FitNesse does: [count:len:item:len:item:...:]
  function ConvertTo-SlimList([object[]]$items) {
    $body = foreach ($i in $items) {
      $s = if ($i -is [array]) { ConvertTo-SlimList $i } else { [string]$i }
      '{0:d6}:{1}:' -f $s.Length, $s
    }
    '[{0:d6}:{1}]' -f $items.Count, ($body -join '')
  }

  function New-SlimStream([string]$text) {
    $stream = [System.IO.MemoryStream]::new([text.encoding]::UTF8.GetBytes($text))
    , $stream
  }
}

Describe 'Get-SlimLength' {
  It 'pads string length to six digits' {
    Get-SlimLength 'abc' | Should -Be '000003'
  }
  It 'returns the element count for arrays' {
    Get-SlimLength @('a', 'bb') | Should -Be '000002'
  }
}

Describe 'ischunk' {
  It 'detects SLIM lists' {
    ischunk '[000000:]' | Should -BeTrue
    ischunk 'bye' | Should -BeFalse
  }
}

Describe 'Test-OneRowTable' {
  It 'is true for a single instruction' {
    Test-OneRowTable @(1, 2, 3) | Should -BeTrue
  }
  It 'is false for a list of instructions' {
    Test-OneRowTable @(@(1, 2, 3), 2, 3) | Should -BeFalse
  }
}

Describe 'Reading messages from the stream' {
  It 'parses the six digit length prefix' {
    get_message_length (New-SlimStream '000220:') | Should -Be 220
  }
  It 'returns -1 for a malformed length' {
    get_message_length (New-SlimStream 'abcdef:') | Should -Be -1
  }
  It 'reads a whole message after its length' {
    $message = ConvertTo-SlimList @(, @('id_0', 'call', 'scriptTableActor', 'eval', '1+1'))
    get_message (New-SlimStream ('{0:d6}:{1}' -f $message.Length, $message)) | Should -Be $message
  }
}

Describe 'Get-SlimTable' {
  It 'turns a SLIM message into instructions' {
    $message = ConvertTo-SlimList @(
      @('scriptTable_0_0', 'make', 'scriptTableActor', 'script'),
      @('scriptTable_0_1', 'call', 'scriptTableActor', 'eval', "'it''s' + 1")
    )
    Get-SlimTable $message
    $script:ps_table.Count | Should -Be 2
    $script:ps_table[1][0] | Should -Be 'scriptTable_0_1'
    $script:ps_table[1][4] | Should -Be "'it''s' + 1"
  }
  It 'keeps empty cells' {
    Get-SlimTable (ConvertTo-SlimList @(, @('id', 'call', 'actor', 'eval', '')))
    $script:ps_table[4] | Should -Be ''
  }
}

Describe 'pack_results' {
  It 'prefixes the UTF-8 byte length and counts the results' {
    $packed = pack_results @('000004:abcd:', '000002:ef:')
    $packed | Should -Be '000031:[000002:000004:abcd:000002:ef:]'
  }
}

Describe 'Process-Instruction' {
  It 'measures scalar results after converting them to text' {
    # Regression: .NET Core formats doubles with more digits than PowerShell's string conversion
    Mock Invoke-SlimInstruction { 'id_0', 1.0060359123456789 }
    $response = Process-Instruction @('id_0')
    $inner = $response.Substring(7, $response.Length - 8)
    [int]$response.Substring(0, 6) | Should -Be $inner.Length
    $inner | Should -Match ':1\.00603591234568:\]$'
  }
}

Describe 'Set-Script' {
  BeforeEach { $slimsymbols.Clear() }

  It 'converts FitNesse hash tables with <name> line endings' -ForEach @(
    @{ name = 'CRLF'; nl = "`r`n" }, @{ name = 'LF'; nl = "`n" }
  ) {
    $html = '<table class="hash_table">' + $nl +
      "`t<tr class=`"hash_row`">" + $nl +
      "`t`t<td class=`"hash_key`">first</td>" + $nl +
      "`t`t<td class=`"hash_value`">'Bob'</td>" + $nl +
      "`t</tr>" + $nl + '</table>'
    Set-Script $html '{0}'
    $Script__ | Should -Be "@{first='Bob';}"
  }

  It 'substitutes string symbols' {
    $slimsymbols['user'] = 'Shawn'
    Set-Script '"hello $user"' '{0}'
    $Script__ | Should -Be '"hello Shawn"'
  }

  It 'leaves typed variables such as parameter declarations alone' {
    $slimsymbols['user'] = 'Shawn'
    Set-Script 'function f([string]$user){ $user }' '{0}'
    $Script__ | Should -Match ([regex]::Escape('([string]$user)'))
  }
}
