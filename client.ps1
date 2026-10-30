#
# "THE BEER-WARE LICENSE" (Revision 42):
# <konstantin.vlasenko@gmail.com> wrote this file. As long as you retain this notice
# you can do whatever you want with this stuff. If we meet some day, and you
# think this stuff is worth it, you can buy me a beer in return.
#
# Remote tables: |script|Remote|host[:port],...| and |Query:Remote|host|code| forward their
# instructions to PowerSlim agents (slim.ps1 <port> server) and share symbols in both directions.

# the timeout for the Remote server is 1 hour
$REMOTE_SERVER_READ_TIMEOUT = 60*60*1000

# Port used for remote targets given without ":port". Override with $env:POWERSLIM_REMOTE_PORT,
# e.g. to use an unprivileged port (ports below 1024 need root on Linux; on macOS they can only bind 0.0.0.0)
function script:Get-RemoteDefaultPort { if($env:POWERSLIM_REMOTE_PORT){ [int]$env:POWERSLIM_REMOTE_PORT } else { 35 } }
# How long to keep retrying a refused connection, e.g. while a just-started remote agent is still binding its port
$REMOTE_SERVER_CONNECT_TIMEOUT = 15000
function script:Connect-RemoteSlim($ps_computer, $ps_port)
{
  $deadline = [DateTime]::UtcNow.AddMilliseconds($REMOTE_SERVER_CONNECT_TIMEOUT)
  while($true){
    try {
      return New-Object System.Net.Sockets.TcpClient($ps_computer, $ps_port)
    }
    catch {
      $socketError = $_.Exception.InnerException -as [System.Net.Sockets.SocketException]
      $refused = $socketError -and $socketError.SocketErrorCode -eq [System.Net.Sockets.SocketError]::ConnectionRefused
      if(!$refused -or [DateTime]::UtcNow -ge $deadline){ throw }
      Start-Sleep -Milliseconds 250
    }
  }
}

# The first instruction of a script or query table says where the table runs. Other tables
# (decision tables, scenarios) keep the current context.
function script:Update-RemoteContext($Instructions) {
  if (!$Instructions.Count -or $Instructions[0] -is [hashtable] -or !$Instructions[0].Count) { return }
  $first = $Instructions[0]
  if ($first[0].StartsWith("scriptTable_") -or $first[0].StartsWith("queryTable_")) {
    if ($first.Count -ge 5 -and "Remote" -eq $first[3]) { Set-RemoteTargets $first[4] }
    else { $script:Remote = $false }
  }
}

# Targets are a comma-separated host[:port] list or, for anything else, an expression that returns them
function script:Set-RemoteTargets([string]$Cell) {
  $script:Remote = $true
  $targets = $null
  if ($Cell -notmatch '^\s*[\w.\-]+(:\d+)?(\s*,\s*[\w.\-]+(:\d+)?)*\s*$') {
    try { $targets = Invoke-UserCode (Expand-SlimSymbols $Cell) }
    catch { Write-Verbose "Remote targets are not an expression: $($_.Exception.Message)" }
    (Get-UserErrors).Clear()
  }
  if ($null -eq $targets) { $targets = $Cell.Split(",") | ForEach-Object { $_.Trim(", ") } | Where-Object { $_ } }
  $script:targets = @($targets | ForEach-Object { "$_".Trim() })
}

# PowerShell code that recreates a symbol value on an agent, or $null for values that cannot be sent.
# Strings travel as base64 so no quote, $ or symbol name in them is ever read as code.
function script:ConvertTo-PowerShellLiteral($Value) {
  $invariant = [Globalization.CultureInfo]::InvariantCulture
  if ($Value -is [string]) {
    return "[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('{0}'))" -f [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Value))
  }
  if ($Value -is [bool]) { if ($Value) { return '$true' } else { return '$false' } }
  if ($Value -is [int] -or $Value -is [long]) { return $Value.ToString($invariant) }
  if ($Value -is [double]) { return "[double]'{0}'" -f $Value.ToString('R', $invariant) }
  $null
}

# Remote results arrive as text; numbers become numbers again
function script:ConvertFrom-RemoteValue([string]$Text) {
  $invariant = [Globalization.CultureInfo]::InvariantCulture
  $int = 0; $long = 0L; $double = 0.0
  if ($Text -match '^\d+$') {
    if ([int]::TryParse($Text, [Globalization.NumberStyles]::None, $invariant, [ref]$int)) { return $int }
    if ([long]::TryParse($Text, [Globalization.NumberStyles]::None, $invariant, [ref]$long)) { return $long }
  }
  elseif ($Text -match '^\d+\.\d+$' -and [double]::TryParse($Text, [Globalization.NumberStyles]::AllowDecimalPoint, $invariant, [ref]$double)) {
    return $double
  }
  $Text
}

# Instructions that recreate our symbols on an agent, except those that came from it: it still has
# the original objects, and their text form would replace them
function script:Get-SymbolSyncMessage([string]$Origin) {
  $instructions = New-Object System.Collections.Generic.List[object]
  foreach ($entry in @($slimsymbols.GetEnumerator())) {
    if ($script:SymbolOrigins.ContainsKey($entry.Key) -and $script:SymbolOrigins[$entry.Key] -eq $Origin) { continue }
    $literal = ConvertTo-PowerShellLiteral $entry.Value
    if ($null -eq $literal) { continue }
    $instructions.Add([object[]]@("symbol_$($instructions.Count)", 'callAndAssign', $entry.Key, 'scriptTableActor', 'eval', $literal))
  }
  if ($instructions.Count) { ConvertTo-SlimString $instructions }
}

# Symbols assigned on the agent (callAndAssign) are copied back from its response
function script:Receive-RemoteSymbols($Instructions, [string]$Response, [string]$Origin) {
  $assigned = @{}
  foreach ($ins in $Instructions) {
    if ($ins -isnot [hashtable] -and $ins.Count -ge 3 -and $ins[1] -eq 'callAndAssign') { $assigned[$ins[0]] = $ins[2] }
  }
  if (!$assigned.Count) { return }
  foreach ($item in (ConvertFrom-SlimList $Response)) {
    try { $pair = ConvertFrom-SlimList $item } catch { continue }
    if ($pair.Count -ne 2 -or !$assigned.ContainsKey($pair[0])) { continue }
    $name = $assigned[$pair[0]]
    # An agent sends nothing back for complex values; forget the symbol rather than store an empty value,
    # so it is not sent over the agent's own variable later (issue #83)
    if ([string]::IsNullOrEmpty($pair[1]) -or $pair[1].StartsWith($slimexception)) {
      [void]$slimsymbols.Remove($name)
      [void]$script:SymbolOrigins.Remove($name)
      continue
    }
    Set-SlimSymbol $name (ConvertFrom-RemoteValue $pair[1]) -Origin $Origin
  }
}

function script:Send-RemoteMessage($Computer, $Port, [string]$Message) {
  $client = Connect-RemoteSlim $Computer $Port
  try {
    $network = $client.GetStream()
    $network.ReadTimeout = $REMOTE_SERVER_READ_TIMEOUT
    try { $stream = New-SlimTlsClientStream $network $Computer }
    catch { throw "TLS handshake with ${Computer}:$Port failed: $($_.Exception.GetBaseException().Message)" }
    # With TLS 1.3 an agent that refuses our certificate does so after the handshake, so it shows up here
    $refused = "The remote agent ${Computer}:$Port closed the connection without answering. It refuses runners whose certificate is not from its CA"
    try {
      Write-SlimMessage $stream $Message
      $reply = Read-SlimMessage $stream -FirstByteTimeout $REMOTE_SERVER_READ_TIMEOUT -Timeout $REMOTE_SERVER_READ_TIMEOUT
    }
    catch { throw "${refused}: $($_.Exception.GetBaseException().Message)" }
    if ($null -eq $reply) { throw $refused }
    $reply
  }
  finally { $client.Close() }
}

# Runs the table on every target and answers with the last target's response
function script:Invoke-RemoteInstructions($Instructions, [string]$Message) {
  try {
    [void](Get-TlsSettings) # agents only accept authenticated runners
    $response = $null
    foreach ($target in $script:targets) {
      $ps_computer, $ps_port = $target.Split(':')
      if ($ps_computer.StartsWith('$')) { $ps_computer = $slimsymbols[$ps_computer.Substring(1)] }
      if ($null -eq $ps_port) { $ps_port = Get-RemoteDefaultPort }
      $origin = "${ps_computer}:$ps_port"

      $sync = Get-SymbolSyncMessage $origin
      if ($sync) {
        Write-Log "Sending symbols to $origin"
        [void](Send-RemoteMessage $ps_computer $ps_port $sync)
      }
      $response = Send-RemoteMessage $ps_computer $ps_port $Message
      Receive-RemoteSymbols $Instructions $response $origin
    }
    $response
  }
  catch {
    $id = if ($Instructions.Count -and $Instructions[0] -isnot [hashtable] -and $Instructions[0].Count) { $Instructions[0][0] } else { '' }
    ConvertTo-SlimString @(, [object[]]@($id, "$slimexception$($_.Exception.Message)"))
  }
}

function script:Test-TcpPort($ps_remotehost, $ps_port)
{
    $ErrorActionPreference = 'SilentlyContinue'
    $s = new-object Net.Sockets.TcpClient
    $s.Connect($ps_remotehost, $ps_port)
    if ($s.Connected) {
        $s.Close()
        return $true
    }
    return $false
}

function script:Wait-RemoteServer($ps_remotehost)
{
    while(!(Test-TcpPort $ps_remotehost 35)){Start-Sleep -Seconds 10}
}
