# Unit tests for slim.ps1 and client.ps1. Run with: Invoke-Pester ./tests
BeforeAll {
  # slim.ps1 starts a server when it runs, so load only the function definitions and top-level
  # constants of both scripts (via the parser) instead of executing them.
  $root = Split-Path -Parent $PSScriptRoot
  $definitions = foreach ($file in 'slim.ps1', 'client.ps1') {
    $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root $file), [ref]$null, [ref]$null)
    $ast.EndBlock.Statements | Where-Object {
      $_ -is [System.Management.Automation.Language.FunctionDefinitionAst] -or
      ($_ -is [System.Management.Automation.Language.AssignmentStatementAst] -and $_.Extent.Text -notmatch 'MyInvocation')
    } | ForEach-Object { $_.Extent.Text }
  }
  . ([scriptblock]::Create($definitions -join "`n"))
  $script:Shell = (Get-Process -Id $PID).Path
  $script:SlimPath = Join-Path $root 'slim.ps1'

  # Build a SLIM list the way FitNesse does: [count:len:item:len:item:...:]
  function ConvertTo-SlimList([object[]]$items) {
    $body = foreach ($i in $items) {
      $s = if ($i -is [array]) { ConvertTo-SlimList $i } else { [string]$i }
      '{0:d6}:{1}:' -f $s.Length, $s
    }
    '[{0:d6}:{1}]' -f $items.Count, ($body -join '')
  }

  function New-SlimStream([string]$text) {
    , [System.IO.MemoryStream]::new([text.encoding]::UTF8.GetBytes($text))
  }

  # Runs one instruction list and returns the response as a list of [id, value] pairs
  function Invoke-Table([object[]]$instructions) {
    $response = Invoke-SlimMessage (ConvertTo-SlimList $instructions) -IgnoreRemote
    foreach ($item in (ConvertFrom-SlimList $response)) { , (ConvertFrom-SlimList $item) }
  }

  # The value returned for one instruction
  function Invoke-Eval([string]$code) {
    (Invoke-Table @(, @('id', 'call', 'scriptTableActor', 'eval', $code)))[1]
  }

  function Reset-Slim {
    $slimsymbols.Clear()
    $script:SymbolOrigins.Clear()
    $script:SLIM_ABORT_TEST = $false
  }

  function Write-Log { }
  # Non-ASCII text built from code points: Windows PowerShell 5.1 reads this file as ANSI
  $script:Emoji = [char]::ConvertFromUtf32(0x1F600)
  $script:Cyrillic = -join [char[]](0x0414, 0x043E, 0x0431, 0x0440, 0x044B, 0x0439)
}

Describe 'SLIM lists' {
  It 'serializes nested lists, counting UTF-16 code units' {
    ConvertTo-SlimString @('a', @('bc', $null), $script:Emoji) |
      Should -Be ('[000003:000001:a:000031:[000002:000002:bc:000004:null:]:000002:{0}:]' -f $script:Emoji)
  }
  It 'uses more than six digits for long items' {
    $long = 'x' * 1000000
    (ConvertTo-SlimString @(, $long)).StartsWith('[000001:1000000:xx') | Should -BeTrue
  }
  It 'parses what it serializes' {
    $text = ConvertTo-SlimString @('a', '', 'it''s [000000:] :colon:', @('nested'))
    $items = ConvertFrom-SlimList $text
    $items.Count | Should -Be 4
    $items[1] | Should -Be ''
    $items[2] | Should -Be 'it''s [000000:] :colon:'
    ConvertFrom-SlimList $items[3] | Should -Be 'nested'
  }
  It 'reads lengths of more than six digits' {
    ConvertFrom-SlimList '[0000001:0000003:abc:]' | Should -Be 'abc'
  }
  It 'rejects <name>' -ForEach @(
    @{ name = 'a missing ['; text = '000001:000001:a:]' }
    @{ name = 'a short length'; text = '[00001:000001:a:]' }
    @{ name = 'an item without its colon'; text = '[000001:000001:ab]' }
    @{ name = 'a wrong item count'; text = '[000002:000001:a:]' }
    @{ name = 'trailing text'; text = '[000001:000001:a:]x' }
  ) {
    { ConvertFrom-SlimList $text } | Should -Throw '*Malformed SLIM list*'
  }
  It 'keeps a malformed instruction for its error response' {
    $instructions = ConvertFrom-SlimInstructions (ConvertTo-SlimList @(@('id', 'call'), 'not a list'))
    $instructions[0] | Should -Be @('id', 'call')
    $instructions[1].Malformed | Should -Be 'not a list'
  }
}

Describe 'Reading and writing messages' {
  It 'reads a message whose length counts UTF-8 bytes' {
    $text = "$script:Cyrillic $script:Emoji"
    $bytes = [text.encoding]::UTF8.GetByteCount($text)
    Read-SlimMessage (New-SlimStream ('{0:d6}:{1}' -f $bytes, $text)) | Should -Be $text
  }
  It 'reads a length of more than six digits' {
    Read-SlimMessage (New-SlimStream '0000003:bye') | Should -Be 'bye'
  }
  It 'returns $null when the connection closes before a message' {
    Read-SlimMessage (New-SlimStream '') | Should -BeNullOrEmpty
  }
  It 'rejects <name>' -ForEach @(
    @{ name = 'a length that is not a number'; text = 'abcdef:' }
    @{ name = 'a short length'; text = '00003:bye' }
    @{ name = 'a truncated message'; text = '000010:abc' }
  ) {
    { Read-SlimMessage (New-SlimStream $text) } | Should -Throw
  }
  It 'prefixes the UTF-8 byte length' {
    $stream = [System.IO.MemoryStream]::new()
    Write-SlimMessage $stream $script:Cyrillic
    [text.encoding]::UTF8.GetString($stream.ToArray()) | Should -Be "000012:$script:Cyrillic"
  }
}

Describe 'Symbol substitution' {
  BeforeEach {
    Reset-Slim
    $slimsymbols['MySymbol'] = "it's `"quoted`" `$x"
    $slimsymbols['suffix'] = 'st'
    $slimsymbols['SymbolPrefix'] = 'test1'
    $slimsymbols['user'] = 'Shawn'
  }

  It 'replaces symbols in text in one pass, using the longest symbol name that exists' {
    $slimsymbols['loop'] = '$suffix'
    Expand-SlimSymbolsInText '$SymbolPrefix_x $loop $unknown' | Should -Be 'test1_x $suffix $unknown'
  }
  It 'leaves variable references in code to the symbol variables' {
    Expand-SlimSymbols '$MySymbol.Length; "$MySymbol"; function f([string]$user){ $user }' |
      Should -Be '$MySymbol.Length; "$MySymbol"; function f([string]$user){ $user }'
  }
  It 'inserts values into single-quoted strings with their quotes doubled' {
    Expand-SlimSymbols "'[`$MySymbol]'" | Should -Be "'[it''s `"quoted`" `$x]'"
  }
  It 'braces a symbol that is a prefix of the name in a double-quoted string' {
    Expand-SlimSymbols '"$SymbolPrefix_test $(Get-Date $SymbolPrefix_test)"' |
      Should -Be '"${SymbolPrefix}_test $(Get-Date $SymbolPrefix_test)"'
  }
  It 'calls a command whose name contains a symbol through &' {
    Expand-SlimSymbols 'te$suffix -Name a$suffix' | Should -Be '& "te$suffix" -Name a$suffix'
  }
  It 'resolves an argument that is a single symbol to the stored object' {
    $slimsymbols['list'] = @(1, 2)
    (Resolve-SlimArgument '$list').Count | Should -Be 2
    Resolve-SlimArgument 'a $user' | Should -Be 'a Shawn'
  }
}

Describe 'Instructions' {
  BeforeEach { Reset-Slim }

  It 'keeps variables and functions between instructions' {
    Invoke-Eval '$a = 1; $c, $d = 3, 4; $a++; function Get-Sum { $a + $c + $d }' | Out-Null
    Invoke-Eval 'Get-Sum' | Should -Be '9'
  }
  It 'keeps test variables apart from PowerSlim''s own' {
    Invoke-Eval '$slimsymbols = "overwritten"; $Remote = $true' | Out-Null
    $slimsymbols.GetType().Name | Should -BeLike 'Dictionary*'
    $script:Remote | Should -BeFalse
  }
  It 'shows $Error to the test code' {
    Invoke-Eval 'try { throw "Expected" } catch { $Error[0].Exception.Message }' | Should -BeLike 'Expected,*'
  }
  It 'stores callAndAssign results as symbols and variables' {
    $response = Invoke-Table @(
      @('id_0', 'callAndAssign', 'Quoted', 'scriptTableActor', 'eval', '"it''s `"x`" `$y; exit"'),
      @('id_1', 'call', 'scriptTableActor', 'eval', '"[$Quoted]" + ''[$Quoted]'' + $Quoted.Length')
    )
    $response[0][1] | Should -Be 'it''s "x" $y; exit'
    $response[1][1] | Should -Be '[it''s "x" $y; exit][it''s "x" $y; exit]17'
  }
  It 'assigns symbols' {
    $response = Invoke-Table @(
      @('id_0', 'assign', 'fromFitNesse', 'v1'),
      @('id_1', 'call', 'scriptTableActor', 'eval', '"$fromFitNesse!"')
    )
    $response[0][1] | Should -Be 'OK'
    $response[1][1] | Should -Be 'v1!'
  }
  It 'sets decision table inputs as variables, with symbols resolved' {
    $slimsymbols['who'] = "O'Brien"
    $response = Invoke-Table @(
      @('d_0', 'make', 'decisionTable_0', '"Hello $name"'),
      @('d_1', 'call', 'decisionTable_0', 'setName', '$who'),
      @('d_2', 'call', 'decisionTable_0', 'execute'),
      @('d_3', 'call', 'decisionTable_0', 'result'),
      @('d_4', 'call', 'decisionTable_0', 'length')
    )
    $response[3][1] | Should -Be "Hello O'Brien"
    $response[4][1] | Should -Be '13'
  }
  It 'reports <name>' -ForEach @(
    @{ name = 'an unknown instruction'; instruction = @('id', 'jump', 'x'); expected = '*MALFORMED_INSTRUCTION*' }
    @{ name = 'a missing method'; instruction = @('id', 'call', 'scriptTableActor', 'deleted1Scenario', '1'); expected = '*NO_METHOD_IN_CLASS deleted1Scenario*' }
    @{ name = 'a missing import'; instruction = @('id', 'import', 'no-such-file.ps1'); expected = '*COULD_NOT_IMPORT*' }
  ) {
    @(Invoke-Table @(, $instruction))[0][1] | Should -BeLike $expected
  }
  It 'answers the rest of the batch after StopTest' {
    $response = Invoke-Table @(
      @('id_0', 'call', 'scriptTableActor', 'eval', 'throw "StopTest"'),
      @('id_1', 'call', 'scriptTableActor', 'eval', '"not run"')
    )
    $response[0][1] | Should -BeLike '__EXCEPTION__:ABORT_SLIM_TEST:message:<<*Test aborted*'
    $response[1][1] | Should -Be '__EXCEPTION__:ABORT_SLIM_TEST:message:<<ABORT_TEST_INDICATED:Test not run>>'
  }
  It 'tags StopSuite as ABORT_SLIM_SUITE' {
    @(Invoke-Table @(, @('id', 'call', 'scriptTableActor', 'eval', 'throw "StopSuite"')))[0][1] |
      Should -BeLike '__EXCEPTION__:ABORT_SLIM_SUITE:*'
  }
  It 'stops the batch after <name>' -ForEach @(
    @{ name = 'IgnoreScriptTest'; tag = '__EXCEPTION__:IGNORE_SCRIPT_TEST:' }
    @{ name = 'IgnoreAllTests'; tag = '__EXCEPTION__:IGNORE_ALL_TESTS:' }
  ) {
    $response = @(Invoke-Table @(
      @('id_0', 'call', 'scriptTableActor', 'eval', "throw '${name}:reason'"),
      @('id_1', 'call', 'scriptTableActor', 'eval', '"not run"')
    ))
    $response.Count | Should -Be 1
    $response[0][1] | Should -Be $tag
  }
  It 'returns the message for eval_error' {
    Invoke-Table @(, @('id', 'call', 'scriptTableActor', 'eval_error', '1/0')) | ForEach-Object { $_[1] } |
      Should -Be 'Attempted to divide by zero.'
  }
  It 'measures scalar results after converting them to text' {
    # Regression: .NET Core formats doubles with more digits than PowerShell's string conversion
    Mock Invoke-SlimInstruction { 1.0060359123456789 }
    $response = Invoke-SlimInstructions @(, [string[]]@('id_0'))
    [int]$response.Substring(1, 6) | Should -Be 1
    $response | Should -Match ':1\.00603591234568:\]:\]$'
  }
  It 'returns query results as rows of [name, value] cells' {
    $response = Invoke-Table @(
      @('q_0', 'make', 'queryTable_0', 'Local', '@{ Name = "Bob"; Tags = @("a", "b") }'),
      @('q_1', 'call', 'queryTable_0', 'query')
    )
    $rows = ConvertFrom-SlimList $response[1][1]
    $cells = foreach ($cell in (ConvertFrom-SlimList $rows[0])) { (ConvertFrom-SlimList $cell) -join '=' }
    $cells | Where-Object { $_ -notlike 'SLIM_COMPUTERNAME=*' } | Should -Be @('Name=Bob', 'Tags=["a","b"]')
  }
}

Describe 'Remote symbols' {
  BeforeEach { Reset-Slim }

  It 'recreates <name> on an agent' -ForEach @(
    @{ name = 'a string with quotes and symbols'; value = "it's `$MySymbol `"x`"" }
    @{ name = 'an int'; value = 42 }
    @{ name = 'a long'; value = 637000000000000000L }
    @{ name = 'a double'; value = 1.12 }
    @{ name = 'a bool'; value = $true }
  ) {
    $slimsymbols['MySymbol'] = 'must not be substituted'
    $literal = ConvertTo-PowerShellLiteral $value
    Expand-SlimSymbols $literal | Should -Be $literal
    $copy = & ([scriptblock]::Create($literal))
    $copy | Should -Be $value
    $copy.GetType() | Should -Be $value.GetType()
  }
  It 'does not send symbols back to the agent they came from' {
    Set-SlimSymbol 'local' 'L'
    Set-SlimSymbol 'remote' 'R' -Origin 'host:35'
    Set-SlimSymbol 'complex' (Get-Date)
    $message = Get-SymbolSyncMessage 'host:35'
    $names = ConvertFrom-SlimList $message | ForEach-Object { (ConvertFrom-SlimList $_)[2] }
    $names | Should -Be @('local')
  }
  It 'copies symbols assigned on the agent from its response' {
    Set-SlimSymbol 'gone' 'old'
    $instructions = ConvertFrom-SlimInstructions (ConvertTo-SlimList @(
      @('s_0', 'callAndAssign', 'num', 'scriptTableActor', 'eval', '1'),
      @('s_1', 'callAndAssign', 'text', 'scriptTableActor', 'eval', '"1.2.3"'),
      @('s_2', 'callAndAssign', 'gone', 'scriptTableActor', 'eval', '$null')
    ))
    Receive-RemoteSymbols $instructions (ConvertTo-SlimList @(@('s_0', '7'), @('s_1', '1.2.3'), @('s_2', ''))) 'host:35'
    $slimsymbols['num'] | Should -BeOfType [int]
    $slimsymbols['text'] | Should -Be '1.2.3'
    $slimsymbols.ContainsKey('gone') | Should -BeFalse
    $script:SymbolOrigins['num'] | Should -Be 'host:35'
  }
}

Describe 'stdin/stdout transport' {
  It 'keeps the protocol channel clean of other output' {
    $psi = [System.Diagnostics.ProcessStartInfo]::new($script:Shell, "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$script:SlimPath`" 1")
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $process = [System.Diagnostics.Process]::Start($psi)
    try {
      $stderr = $process.StandardError.ReadToEndAsync()
      $out = $process.StandardOutput.BaseStream
      $header = ''
      while (($c = $out.ReadByte()) -ne 10) { if ($c -lt 0) { throw 'no header' }; $header += [char]$c }
      $header | Should -Be 'Slim -- V0.5'

      # Host output, console output and a child process writing to its inherited stdout
      $child = "Start-Process '$($script:Shell)' '-NoProfile -Command [Console]::Out.Write(''child'')' -NoNewWindow -Wait"
      $message = ConvertTo-SlimList @(, @('id', 'call', 'scriptTableActor', 'eval', "Write-Host host; [Console]::WriteLine('console'); $child; 'result'"))
      Write-SlimMessage $process.StandardInput.BaseStream $message
      $response = Read-SlimMessage $out -FirstByteTimeout 60000 -Timeout 60000
      (ConvertFrom-SlimList (ConvertFrom-SlimList $response)[0])[1] | Should -Be 'result'

      Write-SlimMessage $process.StandardInput.BaseStream 'bye'
      $process.WaitForExit(30000) | Should -BeTrue
      $out.ReadByte() | Should -Be -1
      $stderr.Result | Should -Match 'host'
      $stderr.Result | Should -Match 'child'
    }
    finally {
      if (!$process.HasExited) { $process.Kill() }
    }
  }
}
