#############
# PowerSlim #
#############
#Requires -Version 5.1
<#
.SYNOPSIS
  SLIM server for FitNesse that runs PowerShell.
  Protocol: https://fitnesse.org/FitNesse/UserGuide/WritingAcceptanceTests/SliM/SlimProtocol.html

.EXAMPLE
  ./slim.ps1 1               # runner on stdin/stdout (what FitNesse starts when SLIM_PORT is not defined)
  ./slim.ps1 8090            # runner on a TCP port (SLIM_PORT defined)
  ./slim.ps1 35 server       # remote agent
#>
[CmdletBinding()]
Param(
  # 1 means stdin/stdout, as in the Java SlimService; any other value is a TCP port
  [Parameter(Mandatory=$True,Position=0)]
   [int]$Port,

   [Parameter(Mandatory=$False, Position=1)]
   [string]$Mode="runner",

   # Interface to listen on. Defaults to loopback: the runner is only ever reached by the local
   # FitNesse process. Remote "server" agents execute arbitrary PowerShell for any caller, so only
   # widen this (e.g. -BindAddress 0.0.0.0) on a trusted, private network.
   [Parameter(Mandatory=$False)]
   [string]$BindAddress="127.0.0.1"
)

$slimver = "Slim -- V0.5`n"
$SLIM_PIPE_PORT = 1
$slimvoid = ""
$slimexception = "__EXCEPTION__:"
$slimsymbols = new-Object 'system.collections.generic.dictionary[string,object]'
# Remote agent ("host:port") each symbol was received from, so it is not sent back and overwritten there
$script:SymbolOrigins = new-Object 'system.collections.generic.dictionary[string,string]'

# How long the rest of a message may take once its first byte arrived (and how long a remote agent waits for one)
$REQUEST_READ_TIMEOUT = 10000
$script:SLIM_ABORT_TEST = $false
$script:SLIM_ABORT_TAG = 'ABORT_SLIM_TEST'
$script:SLIM_STOP_BATCH = $false
$script:Remote = $false
$script:SlimScript = ''
$script:QueryFormat__ = '{0}'
$script:EvalFormat__ = '{0}'
$script:POWERSLIM_PATH = $MyInvocation.MyCommand.Path
$script:POWERSLIM_HOME = Split-Path -Parent $MyInvocation.MyCommand.Path
# Test code runs in the global scope of its own runspace (see Get-UserRunspace)
$script:UserRunspace = $null
$script:UserErrors = $null
$script:QuietProgress = $false
# Runs a table cell: global scope, so variables and functions persist between instructions without
# rewriting the code, like Invoke-Expression did at the script scope. Failures come back as one object
# because a statement-terminating error (e.g. 1/0) would not otherwise stop PowerShell.Invoke().
$script:UserCodeRunner = @'
try { Invoke-Expression $args[0] }
catch { [pscustomobject]@{ PSTypeName = 'PowerSlim.Failure'; ErrorRecord = $_ } }
'@

# A symbol reference as FitNesse writes it: $ followed by a letter and word characters
$script:SymbolReference = [regex]'\$(\p{L}\w*)'

#region SLIM serialization

function New-SlimSyntaxError([string]$Reason) {
  New-Object System.FormatException "Malformed SLIM list: $Reason"
}

# Serializes a string or a (nested) list. Lengths count UTF-16 code units, as the protocol requires.
function ConvertTo-SlimString($Value) {
  if ($null -eq $Value) { return 'null' }
  if ($Value -is [string]) { return $Value }
  if ($Value -is [System.Collections.IList]) {
    $text = New-Object System.Text.StringBuilder
    [void]$text.Append('[').Append($Value.Count.ToString('d6')).Append(':')
    foreach ($item in $Value) {
      $s = ConvertTo-SlimString $item
      [void]$text.Append($s.Length.ToString('d6')).Append(':').Append($s).Append(':')
    }
    [void]$text.Append(']')
    return $text.ToString()
  }
  [string]$Value
}

# Reads "dddddd:" at $Index (six digits or more) and moves $Index past the colon
function Read-SlimLength([string]$Text, [ref]$Index) {
  $start = $Index.Value
  $i = $start
  while ($i -lt $Text.Length -and [int]$Text[$i] -ge 48 -and [int]$Text[$i] -le 57) { $i++ }
  if ($i - $start -lt 6 -or $i -ge $Text.Length -or $Text[$i] -ne [char]':') {
    throw (New-SlimSyntaxError "expected a length of six or more digits and a colon at position $start")
  }
  $Index.Value = $i + 1
  [int]::Parse($Text.Substring($start, $i - $start), [Globalization.CultureInfo]::InvariantCulture)
}

# Parses one SLIM list into the strings it holds. Items are not parsed further: whether an item is a
# nested list depends on where it is used, and a code cell that happens to look like a list stays code.
function ConvertFrom-SlimList([string]$Text) {
  if ([string]::IsNullOrEmpty($Text) -or $Text[0] -ne [char]'[') { throw (New-SlimSyntaxError 'a list starts with [') }
  $i = 1
  $count = Read-SlimLength $Text ([ref]$i)
  $items = New-Object 'System.Collections.Generic.List[string]'
  for ($n = 0; $n -lt $count; $n++) {
    $length = Read-SlimLength $Text ([ref]$i)
    if ($i + $length -ge $Text.Length -or $Text[$i + $length] -ne [char]':') {
      throw (New-SlimSyntaxError "item $n is not terminated by a colon")
    }
    $items.Add($Text.Substring($i, $length))
    $i += $length + 1
  }
  if ($i -ne $Text.Length - 1 -or $Text[$i] -ne [char]']') { throw (New-SlimSyntaxError "expected ] after $count items") }
  , $items.ToArray()
}

# An instruction list: each item is one instruction, itself a list of strings
function ConvertFrom-SlimInstructions([string]$Message) {
  $instructions = New-Object System.Collections.Generic.List[object]
  foreach ($item in (ConvertFrom-SlimList $Message)) {
    try { $instructions.Add([string[]](ConvertFrom-SlimList $item)) }
    catch { $instructions.Add(@{ Malformed = $item }) }
  }
  , $instructions.ToArray()
}

#endregion

#region Transport

function Set-ReadTimeout($Stream, [int]$Milliseconds) {
  if ($Stream.CanTimeout) { $Stream.ReadTimeout = $Milliseconds }
}

function Read-SlimBytes($Stream, [int]$Count) {
  $buffer = New-Object byte[] $Count
  $offset = 0
  while ($offset -lt $Count) {
    $read = $Stream.Read($buffer, $offset, $Count - $offset)
    if ($read -le 0) { throw (New-Object System.IO.EndOfStreamException "Connection closed after $offset of $Count bytes") }
    $offset += $read
  }
  , $buffer
}

# Reads one length-prefixed message (the length counts UTF-8 bytes). Returns $null when the peer closed
# the connection before sending anything. -FirstByteTimeout -1 waits for the next message indefinitely.
function Read-SlimMessage($Stream, [int]$FirstByteTimeout = $REQUEST_READ_TIMEOUT, [int]$Timeout = $REQUEST_READ_TIMEOUT) {
  $digits = New-Object System.Text.StringBuilder
  $one = New-Object byte[] 1
  Set-ReadTimeout $Stream $FirstByteTimeout
  while ($true) {
    if ($Stream.Read($one, 0, 1) -le 0) {
      if ($digits.Length -eq 0) { return $null }
      throw (New-Object System.IO.EndOfStreamException "Connection closed while reading the message length")
    }
    if ($digits.Length -eq 0) { Set-ReadTimeout $Stream $Timeout }
    if ($one[0] -eq 58) { break } # ':'
    if ($one[0] -lt 48 -or $one[0] -gt 57 -or $digits.Length -ge 10) {
      throw (New-Object System.IO.InvalidDataException "Not a SLIM message: the length prefix contains byte $($one[0])")
    }
    [void]$digits.Append([char]$one[0])
  }
  if ($digits.Length -lt 6) { throw (New-Object System.IO.InvalidDataException "Not a SLIM message: the length prefix '$digits' is shorter than six digits") }
  $bytes = Read-SlimBytes $Stream ([int]::Parse($digits.ToString(), [Globalization.CultureInfo]::InvariantCulture))
  [Text.Encoding]::UTF8.GetString($bytes)
}

function Write-SlimMessage($Stream, [string]$Text) {
  $body = [Text.Encoding]::UTF8.GetBytes($Text)
  $head = [Text.Encoding]::ASCII.GetBytes($body.Length.ToString('d6') + ':')
  $Stream.Write($head, 0, $head.Length)
  $Stream.Write($body, 0, $body.Length)
  $Stream.Flush()
}

# FitNesse reads SLIM responses from our stdout, so nothing else may write there. Keep private handles to
# stdin/stdout for the protocol and point the process's standard output at stderr (FitNesse adds stderr to
# the execution log); child processes started by tests then inherit stderr as their stdout too.
function Initialize-StdioTransport {
  $in = [Console]::OpenStandardInput()
  $out = [Console]::OpenStandardOutput()
  try {
    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
      Add-Type -Namespace PowerSlim -Name StdHandles -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError = true)] public static extern System.IntPtr GetStdHandle(int nStdHandle);
[DllImport("kernel32.dll", SetLastError = true)] public static extern bool SetStdHandle(int nStdHandle, System.IntPtr handle);
'@
      [void][PowerSlim.StdHandles]::SetStdHandle(-11, [PowerSlim.StdHandles]::GetStdHandle(-12))
      try {
        # Best effort: children reading stdin would otherwise take SLIM messages
        $script:NullInput = [IO.File]::Open('NUL', 'Open', 'Read')
        [void][PowerSlim.StdHandles]::SetStdHandle(-10, $script:NullInput.SafeFileHandle.DangerousGetHandle())
      } catch { Write-Verbose "stdin stays shared with child processes: $($_.Exception.Message)" }
    }
    else {
      # .NET already holds duplicates of fd 0 and 1 in $in and $out, so the originals can be replaced
      Add-Type -Namespace PowerSlim -Name Libc -MemberDefinition @'
[DllImport("libc", SetLastError = true)] public static extern int dup2(int oldfd, int newfd);
[DllImport("libc", SetLastError = true)] public static extern int open(string path, int flags);
'@
      [void][PowerSlim.Libc]::dup2(2, 1)
      $null_fd = [PowerSlim.Libc]::open('/dev/null', 0)
      if ($null_fd -ge 0) { [void][PowerSlim.Libc]::dup2($null_fd, 0) }
    }
  }
  catch {
    [Console]::Error.WriteLine("PowerSlim: child processes may still write to the SLIM channel: $($_.Exception.Message)")
  }
  $stderr = New-Object System.IO.StreamWriter([Console]::OpenStandardError(), (New-Object System.Text.UTF8Encoding $false))
  $stderr.AutoFlush = $true
  [Console]::SetOut($stderr)
  # Progress bars and ANSI colors would only clutter the execution log
  $global:ProgressPreference = 'SilentlyContinue'
  $script:QuietProgress = $true
  $style = Get-Variable PSStyle -ValueOnly -ErrorAction Ignore
  if ($style) { $style.OutputRendering = 'PlainText' }
  @{ In = $in; Out = $out }
}

#endregion

#region Symbols and user code

# Test code gets its own runspace (sharing this process and host): its variables, functions and $Error
# are its own, so a page cannot overwrite PowerSlim's state and PowerSlim's errors never reach the page
function Get-UserRunspace {
  if ($null -eq $script:UserRunspace) {
    $runspace = [runspacefactory]::CreateRunspace($Host)
    $runspace.ThreadOptions = 'UseCurrentThread'
    $runspace.Open()
    $script:UserRunspace = $runspace
    $script:UserErrors = $runspace.SessionStateProxy.GetVariable('Error')
    if ($script:QuietProgress) { Set-UserVariable 'ProgressPreference' 'SilentlyContinue' }
    # Helpers pages may call
    foreach ($name in 'Test-TcpPort', 'Wait-RemoteServer') {
      $helper = Get-Command $name -CommandType Function -ErrorAction Ignore
      if ($helper) { [void](Invoke-UserCode "function global:$name {$($helper.Definition)}") }
    }
  }
  $script:UserRunspace
}

# The test code's $Error
function Get-UserErrors {
  [void](Get-UserRunspace)
  , $script:UserErrors
}

# Runs test code and writes its output. A terminating error is rethrown after the output that came before it.
function Invoke-UserCode([string]$Code, [switch]$MergeErrors) {
  $runspace = Get-UserRunspace
  $failure = $null
  $ps = [powershell]::Create()
  try {
    $ps.Runspace = $runspace
    [void]$ps.AddScript($script:UserCodeRunner, $false).AddArgument($Code)
    if ($MergeErrors) { $ps.Commands.Commands[0].MergeMyResults('Error', 'Output') }
    try { $output = $ps.Invoke() }
    catch { throw $_.Exception.InnerException } # e.g. exit, or break outside a loop
    foreach ($item in $output) {
      if ($null -ne $item -and $item.PSObject.TypeNames -contains 'PowerSlim.Failure') { $failure = $item.ErrorRecord }
      else { $item }
    }
  }
  finally { $ps.Dispose() }
  if ($failure) { throw $failure }
}

function Get-UserVariable([string]$Name) { (Get-UserRunspace).SessionStateProxy.GetVariable($Name) }
function Set-UserVariable([string]$Name, $Value) { (Get-UserRunspace).SessionStateProxy.SetVariable($Name, $Value) }

# Symbols are also PowerShell variables, so code uses their values (of any type) without any rewriting
function Set-SlimSymbol([string]$Name, $Value, [string]$Origin) {
  $slimsymbols[$Name] = $Value
  if ($Origin) { $script:SymbolOrigins[$Name] = $Origin } else { [void]$script:SymbolOrigins.Remove($Name) }
  Set-UserVariable $Name $Value
}

# FitNesse resolves $SymbolPrefix_test to the symbol SymbolPrefix when no longer symbol name matches
function Find-SlimSymbol([string]$Name) {
  for ($length = $Name.Length; $length -gt 0; $length--) {
    $candidate = $Name.Substring(0, $length)
    if ($slimsymbols.ContainsKey($candidate)) { return $candidate }
  }
  $null
}

# Symbol substitution in plain text (data, not code), in one pass so substituted values are never rescanned
function Expand-SlimSymbolsInText([string]$Text) {
  if (!$slimsymbols.Count -or $Text.IndexOf('$') -lt 0) { return $Text }
  $script:SymbolReference.Replace($Text, [System.Text.RegularExpressions.MatchEvaluator]{
    param($match)
    $name = Find-SlimSymbol $match.Groups[1].Value
    if ($null -eq $name) { return $match.Value }
    [string]$slimsymbols[$name] + $match.Groups[1].Value.Substring($name.Length)
  })
}

# An argument that is exactly one $symbol passes the stored object; anything else is text with symbols replaced
function Resolve-SlimArgument([string]$Text) {
  if ($Text -match '^\$(\p{L}\w*)$' -and $slimsymbols.ContainsKey($Matches[1])) { return , $slimsymbols[$Matches[1]] }
  Expand-SlimSymbolsInText $Text
}

# Symbol substitution in PowerShell code. Symbol values never become code: references the PowerShell
# parser resolves itself are left to the symbol variables, and the rest is rewritten where the token is:
#   'single-quoted'     the value is inserted with its quotes doubled, so it stays a string literal
#   "$SymbolPrefix_x"   becomes "${SymbolPrefix}_x" (FitNesse matches the longest symbol name that exists)
#   te$suffix           a bareword command name, which PowerShell does not expand, becomes & "te$suffix"
function Expand-SlimSymbols([string]$Code) {
  if (!$slimsymbols.Count -or $Code.IndexOf('$') -lt 0) { return $Code }
  $tokens = $null
  $parseErrors = $null
  $ast = [System.Management.Automation.Language.Parser]::ParseInput($Code, [ref]$tokens, [ref]$parseErrors)

  $commandNames = @{}
  foreach ($command in $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true)) {
    $name = $command.CommandElements[0]
    if ($command.InvocationOperator -eq 'Unknown' -and $name.StringConstantType -eq 'BareWord') {
      $commandNames[$name.Extent.StartOffset] = $true
    }
  }

  $edits = New-Object System.Collections.Generic.List[object]
  foreach ($token in $tokens) {
    $start = $token.Extent.StartOffset
    if ($token.Kind -eq 'StringLiteral' -or $token.Kind -eq 'HereStringLiteral') {
      foreach ($match in $script:SymbolReference.Matches($token.Text)) {
        $name = Find-SlimSymbol $match.Groups[1].Value
        if ($null -eq $name) { continue }
        $value = [string]$slimsymbols[$name]
        if ($token.Kind -eq 'StringLiteral') { $value = $value -replace "['\u2018\u2019\u201A\u201B]", '$0$0' }
        elseif ($value -match "[\r\n]['\u2018\u2019\u201A\u201B]@") { continue } # would end the here-string
        $edits.Add([pscustomobject]@{ Start = $start + $match.Index; Length = $name.Length + 1; Text = $value })
      }
    }
    elseif ($token -is [System.Management.Automation.Language.StringExpandableToken]) {
      $inner = New-Object System.Collections.Generic.List[object]
      $references = 0
      $depth = 0
      foreach ($nested in $token.NestedTokens) {
        switch ($nested.Kind.ToString()) {
          { $_ -in 'DollarParen', 'AtParen', 'LParen' } { $depth++ }
          'RParen' { $depth-- }
          'Variable' {
            # $(...) holds code; ${braced} and $scope:names are never symbols
            if ($depth -gt 0 -or $nested.Text.StartsWith('${') -or $nested.Text.Contains(':')) { break }
            $variable = $nested.Text.Substring(1)
            $name = Find-SlimSymbol $variable
            if ($null -eq $name) { break }
            $references++
            if ($name.Length -lt $variable.Length) {
              $inner.Add([pscustomobject]@{ Start = $nested.Extent.StartOffset; Length = $name.Length + 1; Text = '${' + $name + '}' })
            }
          }
        }
      }
      if ($references -and $commandNames.ContainsKey($start)) {
        $text = [System.Text.StringBuilder]::new([string]$token.Text)
        foreach ($edit in ($inner | Sort-Object Start -Descending)) {
          [void]$text.Remove($edit.Start - $start, $edit.Length).Insert($edit.Start - $start, $edit.Text)
        }
        $quoted = $text.ToString() -replace '["\u201C\u201D\u201E]', '`$0'
        $edits.Add([pscustomobject]@{ Start = $start; Length = $token.Text.Length; Text = '& "' + $quoted + '"' })
      }
      else {
        foreach ($edit in $inner) { $edits.Add($edit) }
      }
    }
  }

  $result = [System.Text.StringBuilder]::new($Code)
  foreach ($edit in ($edits | Sort-Object Start -Descending)) {
    [void]$result.Remove($edit.Start, $edit.Length).Insert($edit.Start, $edit.Text)
  }
  $result.ToString()
}

#endregion

#region Results

function Convert-Hashtable-2Object($hashtable){
   $ps_object = New-Object PSObject
   $hashtable.GetEnumerator() | ForEach-Object { Add-Member -inputObject $ps_object -memberType NoteProperty -name $_.Name -value $_.Value }
   Add-Member -inputObject $ps_object -memberType NoteProperty -name "SLIM_COMPUTERNAME" -value $env:COMPUTERNAME
   $ps_object
}

function Convert-KeyValuePair-2Object($kvp){
   New-Object PSObject -Property @{ Key=$kvp.Key; Value=$kvp.Value.ToString(); SLIM_COMPUTERNAME=$env:COMPUTERNAME}
}

function ConvertTo($ps_str) {
  $ps_object = New-Object PSObject
  Add-Member -inputObject $ps_object -memberType NoteProperty -name "Value" -value $ps_str
  Add-Member -inputObject $ps_object -memberType NoteProperty -name "SLIM_COMPUTERNAME" -value $env:COMPUTERNAME
  $ps_object
}

function ConvertTo-SimpleObject($ps_obj){ ConvertTo $ps_obj.ToString() }
function GetNullObject{ ConvertTo "Null" }

# One query table cell: [name, value]
function PropertyTo-Slim($ps_obj,$ps_prop){
  if($null -eq $($ps_obj.$ps_prop)){
    $value = $null
  }
  elseif( $($ps_obj.$ps_prop) -is [string]){
    $value = $($ps_obj.$ps_prop)
  }
  elseif($($ps_obj.$ps_prop) -is [system.array] -or $($ps_obj.$ps_prop) -is [psobject]){
    $value = ConvertTo-Json -Compress -InputObject $($ps_obj.$ps_prop)
  }
  else{
    $value = $($ps_obj.$ps_prop).ToString()
  }
  , @($ps_prop, $value)
}

# Query table result: a list of rows, each a list of [name, value] cells, already serialized
function ResultTo-List($list){
  if($null -eq $list){
    return $slimvoid
  }
  if ($list -isnot [array]){
    return $list
  }
  $rows = New-Object System.Collections.Generic.List[object]
  foreach ($ps_obj in $list){
    if ($ps_obj -is 'system.collections.generic.dictionary[string,object]'){
      $ps_obj = [hashtable] $ps_obj
    }
    if($ps_obj -is [hashtable] ){
      $ps_obj = Convert-Hashtable-2Object $ps_obj
    }
    if($ps_obj -is [string] -or $ps_obj -is [int]){
      $ps_obj = ConvertTo-SimpleObject $ps_obj
    }
    if ($ps_obj -is 'system.collections.generic.keyvaluepair[string,object]'){
      $ps_obj = Convert-KeyValuePair-2Object $ps_obj
    }
    if ($null -eq $ps_obj){
      $ps_obj = GetNullObject
    }
    $row = New-Object System.Collections.Generic.List[object]
    foreach ($property in ($ps_obj | Get-Member -membertype Property, NoteProperty)) {
      $row.Add((PropertyTo-Slim $ps_obj $property.Name))
    }
    $rows.Add($row)
  }
  ConvertTo-SlimString $rows
}

function ResultTo-String($res){
  if($null -eq $res){
    $slimvoid
  }
  else{
    $result = ""
    foreach ($ps_obj in $res){
      if ($null -ne $ps_obj) { $result += $ps_obj.ToString() }
      $result += ","
    }
    $result.TrimEnd(",")
  }
}

function New-SlimException([string]$Message) { "${slimexception}message:<<$Message>>" }

#endregion

#region Execution

# Runs a table cell and turns failures into SLIM exceptions; non-terminating errors are appended as text
function Exec-Script([string]$Script, $error_to_result, [switch]$MergeErrors) {
  # After StopTest/StopSuite the rest of the batch is answered with the same tag, so FitNesse stops the test or the suite
  if ( $script:SLIM_ABORT_TEST )  { return "__EXCEPTION__:${script:SLIM_ABORT_TAG}:message:<<ABORT_TEST_INDICATED:Test not run>>" }

  if ([string]::IsNullOrWhiteSpace($Script)) { return }
  $userErrors = Get-UserErrors
  try {
    # Collected first: when the code fails, the response is the exception alone
    $output = Invoke-UserCode $Script -MergeErrors:$MergeErrors
    $output
  } catch {
    if($error_to_result){
      $_.Exception.Message
      $userErrors.Clear()
    }else{
      # The error stays in $userErrors, so the caller still treats the result as a failure (no symbol assignment)
      $errorType = $_.FullyQualifiedErrorId
      if($errorType -match "^Stop(Test|Suite):?(.*)?"){
        # test or suite can be aborted by throw "StopTest" or throw "StopSuite"
        $script:SLIM_ABORT_TEST = $true
        $script:SLIM_ABORT_TAG = if ($matches[1] -eq 'Suite') { 'ABORT_SLIM_SUITE' } else { 'ABORT_SLIM_TEST' }
        $tag = $script:SLIM_ABORT_TAG
        return "__EXCEPTION__:${tag}:message:<<__EXCEPTION__:${tag}:$($matches[1]) aborted. : Additional Info[ $($_.Exception.ToString())  ]>>"
      } elseif($errorType -match "^Ignore(ScriptTest|AllTests):?(.*)?"){
        # throw "IgnoreScriptTest" skips the rest of the script table, throw "IgnoreAllTests" the rest of the page
        $script:SLIM_STOP_BATCH = $true
        $tag = if ($matches[1] -eq 'AllTests') { 'IGNORE_ALL_TESTS' } else { 'IGNORE_SCRIPT_TEST' }
        # FitNesse counts the row as ignored only for the bare tag, so the reason goes to the execution log
        Write-Log "$errorType"
        return "__EXCEPTION__:${tag}:"
      } elseif($_.Exception -is [System.Net.WebException]){
        $script:SLIM_ABORT_TEST = $true
        $script:SLIM_ABORT_TAG = 'ABORT_SLIM_TEST'
        return "__EXCEPTION__:ABORT_SLIM_TEST:message:<<$($_.Exception.Message)>>"
      } else {
        return "__EXCEPTION__:UnhandledException:message:<<$($_.Exception.ToString())>>"
      }
    }
  }
  if($userErrors.Count) { Print-Error }
}

function Print-Error {
  $nonTerminatingIsException = Get-UserVariable 'NonTerminatingIsException'
  Get-UserErrors | ForEach-Object { $_ } | ForEach-Object {
    $details = ($_ | Out-String)
    if($_.Exception) { $details += $_.Exception.ToString() }
    if($nonTerminatingIsException){
      "__EXCEPTION__:Error:message:<<__EXCEPTION__:Error: Additional Info[ $details ]>>"
    } else {
      $details
    }
  } | Out-String
}

# Turns a table cell into the code to run: FitNesse hash tables, <pre> blocks, symbols, ESXi format
function Set-Script([string]$s, $fmt){
  if([string]::IsNullOrEmpty($s)){ $script:SlimScript = ''; return }
  # FitNesse renders hash tables with platform line endings (CRLF on Windows, LF elsewhere)
  $s = $s -replace '<table class="hash_table">\r?\n', '@{' -replace '</table>','}' -replace '\t*<tr class="hash_row">\r?\n','' -replace '\t*</tr>\r?\n','' -replace '\t*<td class="hash_key">(.*)</td>\r?\n', '$1=' -replace '\t*<td class="hash_value">(.*)</td>\r?\n','$1;'
  if($s -match '^\s*&?<pre>')
  {
    $s = $s -replace '<.?pre>' #workaround fitnesse strange behavior
  }
  $s = Expand-SlimSymbols $s
  if($fmt -and $fmt -ne '{0}'){ $s = $fmt -f $s }
  $script:SlimScript = $s
}

# |get|uri| or |post|uri, body| where the uri may reference variables and the body is PowerShell code
# (sent as JSON). A $headers variable, when the page defines one, is sent with the request.
function Set-RestScript([string]$Method, [string]$Arguments) {
  $uri, $body = ([string]$Arguments) -split ',', 2
  Set-UserVariable 'PowerSlimRequest' @{ Uri = $uri.Trim(); Method = $Method; ContentType = 'application/json' }
  $code = '$PowerSlimRequest.Uri = $ExecutionContext.InvokeCommand.ExpandString($PowerSlimRequest.Uri)' + "`n"
  if ($null -ne $body) { $code += '$PowerSlimRequest.Body = $(' + "`n" + (Expand-SlimSymbols $body) + "`n" + ') | ConvertTo-Json -Depth 3' + "`n" }
  $code += 'if ($null -ne $headers) { $PowerSlimRequest.Headers = $headers }' + "`n"
  $code += 'Invoke-RestMethod @PowerSlimRequest'
  $script:SlimScript = $code
}

function Import-SlimScript([string]$Path) {
  if (![IO.Path]::IsPathRooted($Path)) { $Path = Join-Path (Get-Location).Path $Path }
  try { Invoke-UserCode (". '{0}'" -f ($Path -replace "['\u2018\u2019\u201A\u201B]", '$0$0')) }
  catch { return (New-SlimException "COULD_NOT_IMPORT $Path $($_.Exception.Message)") }
  "OK"
}

function make($ins){
  if("ESXI".Equals($ins[3],[System.StringComparison]::OrdinalIgnoreCase)){
    # esxi.ps1 was imported into the test code's runspace
    Set-UserVariable 'PowerSlimInstruction' $ins
    $script:QueryFormat__ = Invoke-UserCode 'Get-QueryFormat $PowerSlimInstruction'
    $script:EvalFormat__ = Invoke-UserCode 'Get-EvalFormat $PowerSlimInstruction'
  }
  "OK"
}

function Get-PropertyPath($Object, [string]$Path) {
  foreach ($name in $Path.Split('.')) {
    if ($null -eq $Object) { break }
    $Object = $Object.$name
  }
  $Object
}

# A call on a decision table: the code is the table's class name, inputs are set as variables before execute
function Invoke-DecisionTableCall([string]$Method, [string[]]$Arguments, [string]$Symbol) {
  if ($Method -match '^(table|beginTable|reset|endTable)$') { return "/__VOID__/" }
  if ($Method.Length -gt 3 -and $Method.StartsWith('set', [StringComparison]::OrdinalIgnoreCase)) {
    $name = $Method.Substring(3)
    if ($name -notmatch '^\w+$') { return (New-SlimException "NO_METHOD_IN_CLASS $Method decisionTable") }
    Set-UserVariable $name (Resolve-SlimArgument $Arguments[0])
    return "/__VOID__/"
  }
  if ($Method -eq 'execute') {
    (Get-UserErrors).Clear()
    # store the decision table test time.
    $script:decision_time = Measure-Command {
      $script:decision_result = Exec-Script -Script $script:SlimScript -MergeErrors
    }
    return $slimvoid
  }
  switch -regex ($Method) {
    # Support requesting the amount of time it took to process a decision table row.
    # Newer FitNesse versions keep the dot: "Time.Seconds?" arrives as "Time.Seconds"
    '^Time\.?(?<comp>\w+)?$' {
      if (!$Matches.ContainsKey('comp')) { return $script:decision_time.TotalSeconds }
      switch ($matches.comp) {
        'Seconds'      { return $script:decision_time.TotalSeconds }
        'Days'         { return $script:decision_time.TotalDays }
        'Hours'        { return $script:decision_time.TotalHours }
        'Minutes'      { return $script:decision_time.TotalMinutes }
        'Milliseconds' { return $script:decision_time.TotalMilliseconds }
      }
      return "Invalid Duration: $Method"
    }
    '^Result$' {
      if ($Symbol) { Set-SlimSymbol $Symbol $script:decision_result }
      return (ResultTo-String $script:decision_result)
    }
    # The properties of complex results are referenced with _ in place of . (Phone_Home is .Phone.Home)
    '^(?:Result)?(\S+)$' {
      $value = Get-PropertyPath $script:decision_result ($Matches[1] -replace '_','.')
      if ($Symbol) { Set-SlimSymbol $Symbol $value }
      return (ResultTo-String $value)
    }
  }
  'Not Implemented'
}

function Invoke-SlimCall([string]$Instance, [string]$Method, [string[]]$Arguments, [string]$Symbol) {
  if ($Instance.StartsWith('decisionTable')) { return (Invoke-DecisionTableCall $Method $Arguments $Symbol) }

  $action, $error_to_result = $Method.Split('_', 2)
  $isRest = 'get','post','patch','put','delete' -contains $action
  if ($action -eq 'cloneSymbol') {
    # FitNesse copies a scenario output into a decision table symbol with cloneSymbol $output
    $value = Resolve-SlimArgument $Arguments[0]
    if ($Symbol) { Set-SlimSymbol $Symbol $value }
    return (ResultTo-String $value)
  }
  if (!$isRest -and 'eval','query' -notcontains $action) {
    # table, beginTable, reset, endTable... on query tables; anything else is a missing method
    if ($Instance -eq 'scriptTableActor') { return (New-SlimException "NO_METHOD_IN_CLASS $Method PowerSlim") }
    return $slimvoid
  }

  if ($action -eq 'eval') { Set-Script $Arguments[0] $script:EvalFormat__ }
  elseif ($isRest) { Set-RestScript $action $Arguments[0] }
  $userErrors = Get-UserErrors
  $userErrors.Clear()
  # Measure the amount of time this step or command takes
  $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
  $result = Exec-Script -Script $script:SlimScript $error_to_result
  $script:Command_Time = $stopwatch.Elapsed
  Write-Log $script:SlimScript : $script:Command_Time.TotalSeconds

  if($userErrors.Count) {
    $userErrors.Clear()
    return (ResultTo-String $result)
  }
  if($Symbol){ Set-SlimSymbol $Symbol $result }
  if ($action -eq 'query') {
    if(($null -eq $result) -or ($result -is 'system.collections.generic.dictionary[string,object]' -and $result.Count -eq 0)){
      $result = ResultTo-List @()
    }
    else{
      $result = ResultTo-List @($result)
    }
  }
  elseif ($action -eq 'eval') { $result = ResultTo-String $result }
  else {
    Set-UserVariable $action $result
    if ($result -is [String]) { $result = ResultTo-String $result }
    else { $result = ResultTo-List @($result) }
  }
  if ($result -is [String]) { $result.TrimEnd([char[]]"`r`n") } else { $result }
}

function Get-InstructionArguments($Instruction, [int]$From) {
  if ($Instruction.Count -gt $From) { , [string[]]$Instruction[$From..($Instruction.Count - 1)] }
  else { , [string[]]@() }
}

function Get-MalformedInstruction($Instruction) {
  $text = if ($Instruction -is [hashtable]) { $Instruction.Malformed } else { $Instruction -join ', ' }
  New-SlimException "MALFORMED_INSTRUCTION [$text]"
}

function Invoke-SlimInstruction($Instruction) {
  if ($Instruction -is [hashtable] -or $Instruction.Count -lt 2) { return (Get-MalformedInstruction $Instruction) }
  $ins = $Instruction
  switch -exact ($ins[1]) {
    'import' {
      if ($ins.Count -ne 3) { break }
      return (Import-SlimScript $ins[2])
    }
    'make' {
      if ($ins.Count -lt 4) { break }
      $result = make $ins
      # query tables keep their code in the last argument, decision tables in the class name
      Set-Script $ins[$ins.Count - 1] $script:QueryFormat__
      return $result
    }
    'assign' {
      if ($ins.Count -ne 4) { break }
      Set-SlimSymbol $ins[2] $ins[3]
      return "OK"
    }
    'call' {
      if ($ins.Count -lt 4) { break }
      return (Invoke-SlimCall $ins[2] $ins[3] (Get-InstructionArguments $ins 4))
    }
    'callAndAssign' {
      if ($ins.Count -lt 5) { break }
      return (Invoke-SlimCall $ins[3] $ins[4] (Get-InstructionArguments $ins 5) -Symbol $ins[2])
    }
  }
  Get-MalformedInstruction $ins
}

# The response value of one instruction: a string (lists are already serialized)
function Get-SlimInstructionResult($Instruction) {
  try { $output = @(Invoke-SlimInstruction $Instruction) }
  catch { return (New-SlimException "$($_.Exception.Message)") }
  if (!$output.Count -or $null -eq $output[0]) { return $slimvoid }
  # Stringify scalars once so the SLIM length matches the serialized text. On .NET Core,
  # Double.ToString() is round-trip precise while PowerShell string conversion uses 15 digits.
  [string]$output[0]
}

function Invoke-SlimInstructions($Instructions) {
  $script:SLIM_STOP_BATCH = $false
  $responses = New-Object System.Collections.Generic.List[object]
  foreach ($instruction in $Instructions) {
    # IgnoreScriptTest / IgnoreAllTests: FitNesse ignores the rest of the table, so do not run it
    if ($script:SLIM_STOP_BATCH) { break }
    $id = if ($instruction -isnot [hashtable] -and $instruction.Count) { $instruction[0] } else { '' }
    $value = Get-SlimInstructionResult $instruction
    $responses.Add([object[]]@($id, $value))
  }
  ConvertTo-SlimString $responses
}

# Executes one instruction list and returns the serialized response list
function Invoke-SlimMessage([string]$Message, [switch]$IgnoreRemote) {
  $script:SLIM_ABORT_TEST = $false
  $script:QueryFormat__ = $script:EvalFormat__ = '{0}'
  try { $instructions = ConvertFrom-SlimInstructions $Message }
  catch {
    Write-Log "Ignoring a message that is not an instruction list: $($_.Exception.Message)"
    return (ConvertTo-SlimString @())
  }
  if (!$IgnoreRemote) {
    Update-RemoteContext $instructions
    if ($script:Remote) { return (Invoke-RemoteInstructions $instructions $Message) }
  }
  Invoke-SlimInstructions $instructions
}

#endregion

#region Servers

function Start-SlimRunner($Reader, $Writer) {
  $header = [Text.Encoding]::ASCII.GetBytes($slimver)
  $Writer.Write($header, 0, $header.Length)
  $Writer.Flush()
  while ($true) {
    try {
      $message = Read-SlimMessage $Reader -FirstByteTimeout -1
      if ($null -eq $message -or $message -eq 'bye') { return }
      Write-SlimMessage $Writer (Invoke-SlimMessage $message)
    }
    catch {
      Write-Log "Connection to FitNesse lost: $($_.Exception.Message)"
      return
    }
  }
}

# A remote agent answers one instruction list per connection
function Start-RemoteAgent($Listener) {
  while ($true) {
    Write-Log "waiting..."
    $client = $Listener.AcceptTcpClient()
    Write-Log "accepted!"
    try {
      $stream = $client.GetStream()
      $message = Read-SlimMessage $stream
      if ($null -ne $message) { Write-SlimMessage $stream (Invoke-SlimMessage $message -IgnoreRemote) }
    }
    catch { Write-Log "Dropped connection: $($_.Exception.Message)" }
    finally { $client.Close() }
  }
}

function Start-PowerSlim([int]$Port, [string]$Mode, [string]$BindAddress) {
  if ($Port -eq $SLIM_PIPE_PORT) {
    if ($Mode -ne 'runner') { throw "Port $SLIM_PIPE_PORT means stdin/stdout, which only the runner supports" }
    $pipe = Initialize-StdioTransport
    Write-Log "========== Starting SLIM runner on stdin/stdout =========="
    Start-SlimRunner $pipe.In $pipe.Out
    return
  }

  Write-Log "========== Starting SLIM $Mode on ${BindAddress}:$Port =========="
  $listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Parse($BindAddress), $Port)
  $listener.Start()
  try {
    if ($Mode -eq "runner") {
      $client = $listener.AcceptTcpClient()
      try {
        $stream = $client.GetStream()
        Start-SlimRunner $stream $stream
      }
      finally { $client.Close() }
    }
    else {
      Start-RemoteAgent $listener
    }
  }
  finally { $listener.Stop() }
}

function Write-Log (){
  $timestamp = Get-Date -f "dd.MM.yy HH:mm:ss.fff"
  Write-Host $timestamp"`t"$args
}

#endregion

. (Join-Path $script:POWERSLIM_HOME 'client.ps1')
Start-PowerSlim -Port $Port -Mode $Mode -BindAddress $BindAddress
