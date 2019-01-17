######################
# PowerSlim 20170303 #
######################
[CmdletBinding()]
Param(
  [Parameter(Mandatory=$True,Position=0)]
   [int]$Port,
	
   [Parameter(Mandatory=$False, Position=1)]
   [string]$Mode="runner"
)

$slimver = "Slim -- V0.3`n"
$slimnull = "000004:null:"
#$slimvoid = "/__VOID__/"
$slimvoid = ""
$slimexception = "__EXCEPTION__:"
$slimsymbols = new-Object 'system.collections.generic.dictionary[string,object]'
#$slimbuffer = new-object byte[] 102400
#$slimbuffersize = 0
#$VerbosePreference="Continue"

#Support for slow connection
#$ps_stream.ReadTimeout = 10000 #idea is that the client should send data, so the stream is in the read mode. We can wait 10 seconds or more?
$REQUEST_READ_TIMEOUT = 10000
$script:SLIM_ABORT_TEST = $false
$script:SLIM_ABORT_SUITE = $false
$script:POWERSLIM_PATH = $MyInvocation.MyCommand.Path
$script:POWERSLIM_HOME = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:NonTerminatingIsException = $false

function Get-SlimTable($slimchunk){

  $ps_exp = $slimchunk -replace "'","''" -replace "000000::","000000:blank:"  -replace "(?S):\d{6}:(.*?)(?=(:\d{6}:|:\]))",',''$1''' -replace "'(\[\d{6})'", '$1' -replace ":\d{6}:", "," -replace ":\]", ")" -replace "\[\d{6},", "(" -replace "'blank'", "''"

  $script:ps_table = iex $ps_exp
}


function Test-OneRowTable($ps_table){
  !($ps_table[0] -is [array])
}

function SlimException-NoClass($ps_class){
  $slimexception + "NO_CLASS " + $ps_class
}

function SlimException-CMD_NOT_FOUND($ps_cmd){
  $slimexception + "COMMAND_NOT_FOUND " + $ps_cmd
}

new-alias noclass SlimException-NoClass
new-alias nocommand SlimException-CMD_NOT_FOUND

function Get-SlimLength($ps_obj){
  if($ps_obj -is [array]){
    $ps_obj.Count.ToString("d6")
  }
  elseif($ps_obj -is 'system.collections.generic.keyvaluepair[string,object]'){
    (1).ToString("d6")
  }
  else {
    $ps_obj.ToString().Length.ToString("d6")
  }
}
new-alias slimlen Get-SlimLength

function ischunk($ps_msg){
  $ps_msg.StartsWith('[') -and $ps_msg.EndsWith(']')
}

function send_slim_version($ps_stream){
  $ps_version = [text.encoding]::ascii.getbytes($slimver)
  $ps_stream.Write($ps_version, 0, $ps_version.Length)
}

$ps_buf1 = $null
$ps_buf2 = $null

function get_message_length($ps_stream){

  $script:ps_buf1 = new-object byte[] 7

  $t = read_message $ps_stream $ps_buf1
  $str = [text.encoding]::utf8.getstring($ps_buf1, 0, 6)
  $res = $null
  if([int32]::TryParse($str, [ref]$res))
  {
    $res
  } else
  {
    Write-Verbose "Bad length!"
    -1
  }

  Write-Verbose "Length: $ps_buf1"
}

function read_message($ps_stream, $buf, $offset = 0){

    Write-Verbose "Reading message...."
    # But if the read operation completed with the zero bytes. This means that client is not going to send anything. Right?
    
    $ps_size = $buf.Count

    while($offset -lt $ps_size){

        $error.clear()
        $offset += $ps_stream.Read($buf, $offset, $ps_size - $offset)

        Write-Verbose "Offset $offset"

        if ($error) {
            Write-Verbose $error.Exception
            break
        }
        if($offset -eq 0)
        {
            Write-Verbose "Offset should not be zero!"
            break
        }
        
    }

    Write-Verbose "Got $buf"
}

function get_message($ps_stream){

  Write-Verbose "Getting Message Length ..."

  $ps_size = get_message_length($ps_stream)

  Write-Verbose "Length: $ps_size"
  if($ps_size -lt 0)
  {
    " "
    return
  }

  $script:ps_buf2 = new-object byte[] $ps_size
  $t = read_message $ps_stream $ps_buf2
  [text.encoding]::utf8.getstring($ps_buf2)

}

function ObjectTo-Slim($ps_obj){
  $slimview = "[000002:" + (slimlen $ps_prop) + ":" + $ps_prop+ ":"
  if($($ps_obj.$ps_prop) -eq $null -or $($ps_obj.$ps_prop) -is [system.array]){
    $slimview += $slimnull + "]"
  }
  else{
    $slimview += (slimlen $($ps_obj.$ps_prop)) + ":" + $($ps_obj.$ps_prop).ToString() + ":]"
  }
  (slimlen $slimview) + ":" + $slimview + ":"
}

function ConvertTo-Json20([object] $item)
{
    add-type -assembly system.web.extensions
    $ps_js=new-object system.web.script.serialization.javascriptSerializer
    return $ps_js.Serialize($item) 
}

function PropertyTo-Slim($ps_obj,$ps_prop){
  $slimview = "[000002:" + (slimlen $ps_prop) + ":" + $ps_prop+ ":"
  if($($ps_obj.$ps_prop) -eq $null){
    $slimview += $slimnull + "]"
  }
  elseif( $($ps_obj.$ps_prop) -is [string]){
    $slimview += (slimlen $($ps_obj.$ps_prop)) + ":" + $($ps_obj.$ps_prop) + ":]"
  }
  elseif($($ps_obj.$ps_prop) -is [system.array] -or $($ps_obj.$ps_prop) -is [psobject]){
    if ($Host.Version.Major -ge 3) { $slimview += (ConvertTo-Json -Compress $($ps_obj.$ps_prop)) |% {(slimlen $_) + ":" + $_.ToString() + ":]"} }
        else { $slimview += ConvertTo-JSON20 ($ps_obj.$ps_prop) |% {(slimlen $_) + ":" + $_.ToString() + ":]"} }        
  }
  else{
    $slimview += (slimlen $($ps_obj.$ps_prop)) + ":" + $($ps_obj.$ps_prop).ToString() + ":]"
  }
  (slimlen $slimview) + ":" + $slimview + ":"
}

function Convert-Hashtable-2Object($hashtable){
   $ps_object = New-Object PSObject
   $hashtable.GetEnumerator() | % { Add-Member -inputObject $ps_object -memberType NoteProperty -name $_.Name -value $_.Value }
   Add-Member -inputObject $ps_object -memberType NoteProperty -name "SLIM_COMPUTERNAME" -value $env:COMPUTERNAME
   $ps_object
}

function Convert-KeyValuePair-2Object($kvp){
   $ps_obj = New-Object PSObject -Property @{ Key=$kvp.Key; Value=$kvp.Value.ToString(); SLIM_COMPUTERNAME=$env:COMPUTERNAME}
   $ps_obj
}

function ConvertTo($ps_str) {

  $ps_object = New-Object PSObject

  Add-Member -inputObject $ps_object -memberType NoteProperty -name "Value" -value $ps_str
  Add-Member -inputObject $ps_object -memberType NoteProperty -name "SLIM_COMPUTERNAME" -value $env:COMPUTERNAME

  $ps_object

}

function ConvertTo-SimpleObject($ps_obj){ ConvertTo $ps_obj.ToString() }
function GetNullObject{ ConvertTo "Null" }

function isgenericdict($list){
	$list -is [array] -and $list.Count -eq 1 -and $list[0] -is 'system.collections.generic.dictionary[string,object]'
}

function ResultTo-List($list){
  if($null -eq $list){
    $slimvoid
  }
  elseif ($list -is [array]){
    $result = "[" + (slimlen $list) + ":"
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
      $fieldscount = ($ps_obj  | gm -membertype Property, NoteProperty  | measure-object).Count
      $itemstr = "[" +  $fieldscount.ToString("d6") + ":"
      $ps_obj  | gm -membertype Property, NoteProperty | % {$itemstr += PropertyTo-Slim $ps_obj $_.Name }
      $itemstr += "]"
    
      $result += (slimlen $itemstr) + ":" + $itemstr + ":"
    } 
    $result += "]"
    $result
  }
  else{
    $list
  }
}

function ResultTo-String($res){
  if($res -eq $null){
    $slimvoid
  }
  else{
    $result = ""
    foreach ($ps_obj in $res){
      $result += $ps_obj.ToString()
      $result += ","
    }
    $result.TrimEnd(",")
  }
}

function Exec-Script( $Script, $error_to_result) {
    if ( $script:SLIM_ABORT_TEST )  { return "__EXCEPTION__:ABORT_SLIM_TEST:message:<<ABORT_TEST_INDICATED:Test not run>>" }
    if ( $script:SLIM_ABORT_SUITE ) { return "__EXCEPTION__:ABORT_SLIM_TEST:message:<<ABORT_SUITE_INDICATED:Test not run>>" }
   
   try { 
        iex $Script        
        $script:matches = $matches # preserve the $matches value, if set by the expression
   } catch { 
        if($error_to_result){
          $_.Exception.Message
          $error.clear()
        }else{
          $errorType = $Error[0].FullyQualifiedErrorId
          if($errorType -match "^Stop(Test|Suite):?(.*)?"){
              # test or suite can be aborted by throw "StopTest"            
              $script:SLIM_ABORT_TEST = $true
              if ($matches[1] -eq 'Suite') {
                $script:SLIM_ABORT_SUITE = $true
              }
              "__EXCEPTION__:ABORT_SLIM_TEST:message:<<__EXCEPTION__:ABORT_SLIM_TEST:$($matches[1]) aborted. : Additional Info[ $($_.Exception.ToString())  ]>>"
              "__EXCEPTION__:ABORT_SLIM_TEST:message:<<$($_.Exception.ToString())>>"
          } else {
              if($_.Exception -is [System.Net.WebException]){
                $script:SLIM_ABORT_TEST = $true
                "__EXCEPTION__:ABORT_SLIM_TEST:message:<<$($_.Exception.Message)>>"
              }else{
                "__EXCEPTION__:UnhandledException:message:<<$($_.Exception.ToString())>>"
              }
          }
        }
   }
   if($Error[0] -ne $null) { Print-Error }
}

function Print-Error {
    $Error | % {
      $details = ($_ | Out-String)
      if($_.Exception) { $details += $_.Exception.ToString() }
      if($script:NonTerminatingIsException){
          "__EXCEPTION__:Error:message:<<__EXCEPTION__:Error: Additional Info[ $details ]>>"
      } else {
          $details
      }
    } | Out-String
}

function Invoke-SlimCall($fnc){
  $ps_action, $error_to_result = $fnc.split('_');
  if('eval','query','get','post','patch','put','delete' -contains $ps_action){
    $result = Exec-Script -Script $Script__ $error_to_result
  }
  else { 
    if ((Table-Type) -eq "ScriptTableActor") { $result = nocommand $_ }
    else{ $result = $slimvoid }
  }
  $script:matches = $matches
  $result
}

function Set-RestScript($method, $arguments)
{ 
  $uri, $body = $arguments -split ','
  if($body -ne $null) {
    $s = "Invoke-RestMethod {0} -Body '{1}' -Method {2} -ContentType 'application/json'" -f $uri,(iex $body | ConvertTo-JSON -Depth 3),$method
  }
  else {
    $s = "Invoke-RestMethod {0} -Method {1} -ContentType 'application/json'" -f $uri, $method
  }
  if($headers -ne $null){
    $s += ' -Headers $script:headers'
  }
  #$s = "($s) | ConvertFrom-JSON"

  Set-Variable -Name Script__ -Value $s -Scope Global
}

function Set-Script($s, $fmt){
  if(!$s){ return }
  $s = $s -replace '<table class="hash_table">\r\n', '@{' -replace '</table>','}' -replace '\t*<tr class="hash_row">\r\n','' -replace '\t*</tr>\r\n','' -replace '\t*<td class="hash_key">(.*)</td>\r\n', '$1=' -replace '\t*<td class="hash_value">(.*)</td>\r\n','$1;'
  if($s -match '^\s*&?<pre>')
  {
	$s = $s -replace '<.?pre>' #workaround fitnesse strange behavior
  }
  if($slimsymbols.Count){$slimsymbols.Keys | Sort Length -Descending | ? {!($s -cmatch "\`$$_\s*=")} | ? {$slimsymbols[$_] -is [string] } | % {$s=$s -creplace "\`$$_",$slimsymbols[$_] }}
  if($slimsymbols.Count){$slimsymbols.Keys | % { Set-Variable -Name $_ -Value $slimsymbols[$_] -Scope Global}}
  $s = $fmt -f $s
  if($s.StartsWith('function',$true,$null)){Set-Variable -Name Script__ -Value ($s -replace 'function\s+(.+)(?=\()','function script:$1') -Scope Global}
  else{Set-Variable -Name Script__ -Value ($s -replace '\$(?![\$_])(\w+)((?=\s*[\+|\*|\-|\/|%]*=)|(?=\s*,\s*\$\w+.*=))*','$script:$1') -Scope Global}
}

function make($ins){
  if("ESXI".Equals($ins[3],[System.StringComparison]::OrdinalIgnoreCase)){
    $script:QueryFormat__ = Get-QueryFormat $ins
    $script:EvalFormat__ = Get-EvalFormat $ins
  }
  "OK"
}

function Id() {$script:ps_row[0]}
function Operation() {$script:ps_row[1]}
function Module() {$script:ps_row[2]}
function Table-Type() {$script:ps_row[2]}

function Invoke-SlimInstruction(){

  $ins = $script:ps_row

  (Id)

  switch -wildcard (Operation){

    "import" {

      iex ". .\$(Module)" 
      "OK"
      return

    }

    "make" {
    
      make $ins
      Set-Script $ins[$ins.Count - 1] $QueryFormat__
      return
      
    }

    "callAndAssign" {
    
      $symbol = $ins[2]
      $ins = $ins[0,1 + 3 .. $ins.Count]
    }

    "call*" { 
      if($ins[2].StartsWith('decisionTable')){
        if($ins[3] -match ('table|beginTable|reset|endTable')){
          "/__VOID__/"
          return
        }elseif($ins[3][0..2] -join '' -eq 'set'){
          iex "`$script:$($ins[3].Substring(3))='$($ins[4])'"
          "/__VOID__/"
          return
        }elseif($ins[3] -eq 'execute'){
             # store the decision table test time.
             $script:decision_time = measure-command {
               $script:decision_result = Exec-Script -Script "$Script__ 2>&1"
             }
          $slimvoid
          #$script:decision_result
          return
        }else{
          #if($ins[3] -ne 'Result'){
          #  "Not Implemented"
          #}else{
          #  if($symbol){$slimsymbols[$symbol] = $script:decision_result}
          #  $script:decision_result
          #}
             switch -regex ($ins[3]) {
               # Support requesting the amount of time it took to process a decision table row.
               '^Time(?<comp>\w+)?'     
                          { if ( $Matches.ContainsKey( 'comp') ) {
                              switch ( $matches.comp ) {
                                 'Seconds'      { $script:decision_time.TotalSeconds }
                                 'Days'         { $script:decision_time.TotalDays }
                                 'Hours'        { $script:decision_time.TotalHours }
                                 'Minutes'      { $script:decision_time.TotalMinutes }
                                 'Milliseconds' { $script:decision_time.TotalMilliseconds }
                                 default        { 'Invalid Duration: $_' }
                              }
                            } else {
                              $script:decision_time.TotalSeconds 
                            }
                            break
                          }
               '^Result$'   { ResultTo-String ($script:decision_result)
                              if ($symbol) {
                                $slimsymbols[$symbol] = $script:decision_result
                              }
                              break
                            }
               '^Result(\S+)$'   
                            { $prop = $Matches[1]
                              $prop = $prop -replace '_','.'
                              ResultTo-String (iex ('$script:decision_result.'+$prop))
                              if ($symbol) {
                                $slimsymbols[$symbol] = iex ('$script:decision_result.'+$prop)
                              }
                              break
                            }
               '^(\S+)$'    { $prop = $Matches[1]
                              $prop = $prop -replace '_','.'
                              ResultTo-String (iex ('$script:decision_result.'+$prop))
                              if ($symbol) {
                                $slimsymbols[$symbol] = iex ('$script:decision_result.'+$prop)
                              }
                            }
               default    { 'Not Implemented'       }
             }
          return
        }
      }
    }
  }

  $ps_action = $ins[3].split('_')[0];
  if($ps_action -ne "query" -and $ps_action -ne "table"){
    if('get','post','patch','put','delete' -contains $ps_action){
      Set-RestScript $ps_action $ins[4]
    }
    else{
      Set-Script $ins[4] $EvalFormat__
    }
  }
  
  $error.clear()
  # Measure the amount of time this step or command takes
  $script:Command_Time = measure-command {
    # Execution of the test's code occurs here. During the 'make' step this is simple
    # the execution of the 'make' procedure.
    $result = Invoke-SlimCall $ins[3]
  }
  Write-Log $Script__ : $script:Command_Time.TotalSeconds

  
  if($error[0] -ne $null) {
    $error.clear()
    ResultTo-String $result
  }else {
    if($symbol){$slimsymbols[$symbol] = $result}
    $error.clear()
    switch ($ps_action){
      "query" {
        if(($null -eq $result) -or ($result -is 'system.collections.generic.dictionary[string,object]' -and  $result.Count -eq 0)){ 
          $result = ResultTo-List @()
        }
        else{
          $result = ResultTo-List @($result)
        }
      }
      "eval"  { $result = ResultTo-String $result }

      {$_ -match '^(get|post|patch|put|delete)$'}{ 
        Set-Variable -Name $_ -Value ($result) -Scope Global;
        if ($result -is [String]){ 
          $result = ResultTo-String $result 
        }else {
          $result = ResultTo-List @($result)
        }
      }
    }
    if ($result -is [String]) {
      $result.TrimEnd("`r`n")
    } else { 
      $result
    }
  }
}

function Process-Instruction($ins){
  $script:ps_row = $ins
  $result = Invoke-SlimInstruction

  $s = '[000002:' + (slimlen $result[0]) + ':' + $result[0] + ':' + (slimlen $result[1]) + ':' + $result[1] + ':]'
  (slimlen $s) + ":" + $s + ":"

}

function pack_results($results){
  if($results -is [array]){
    $ps_send = "[" + (slimlen $results) + ":"
    $results | % {$ps_send += $_}
  }
  else{
    $ps_send = "[000001:$results"
  }
  $ps_send += "]"
  [text.encoding]::utf8.getbytes($ps_send).Length.ToString("d6") + ":" + $ps_send
}


function check_remote($ps_table) {
  
  if( !(Test-OneRowTable $ps_table) ) {
         
      $ps_table = $ps_table[0]
  }

  if($ps_table[0].StartsWith("scriptTable_") -or $ps_table[0].StartsWith("queryTable_")){

      if("Remote" -eq $ps_table[3])
      {
        set_remote_targets($ps_table[4])
      }
      else
      {
        $script:Remote = $false
      }

  }

}

function set_remote_targets($ps_cell) {

  $script:Remote = $true
  $script:targets = $null

  $script:targets = iex $ps_cell
  
  if($script:targets -eq $null){
    $script:targets = $ps_cell.Split(",") | %{$_.Trim(", ")}
  }

}

function process_table() {

  if(Test-OneRowTable $script:ps_table){ $ps_results = Process-Instruction $script:ps_table }
  else { $ps_results = $script:ps_table | % { Process-Instruction $_ } }

  $ps_results

}

function process_message($ps_stream){

  if( ! $ps_stream.CanRead ){ return "bye" }

  Write-Verbose "Started processing message."

  $script:SLIM_ABORT_TEST = $false
  $error.clear()
  $ps_msg = get_message($ps_stream)

  $ps_msg

  if ($error) { return "bye" }

  if( !(ischunk $ps_msg) ){ return }

  $script:QueryFormat__ = $script:EvalFormat__ = "{0}"
  Get-SlimTable $ps_msg

  check_remote($script:ps_table)

  if($Remote -eq $true){

    Write-Verbose "Buffer1 $ps_buf1"
    Write-Verbose "Buffer2 $ps_buf2"

    Write-Verbose "Processing table remotelly"

    process_table_remotely $script:ps_table $ps_stream;

    Write-Verbose "Done remote call"

    return
  }
  
  $ps_results = process_table

  $ps_send = [text.encoding]::utf8.getbytes((pack_results $ps_results))
  $ps_stream.Write($ps_send, 0, $ps_send.Length)
  
}

function process_message_ignore_remote($ps_stream){

  Write-Verbose "Process Message & Ignore Remote"
  $script:SLIM_ABORT_TEST = $false

  $ps_msg = get_message($ps_stream)

  if(ischunk($ps_msg)){

    $script:QueryFormat__ = $script:EvalFormat__ = "{0}"
    $ps_table = Get-SlimTable $ps_msg

    $ps_results = process_table

    $ps_send = [text.encoding]::utf8.getbytes((pack_results $ps_results))
    $ps_stream.Write($ps_send, 0, $ps_send.Length)

  }
}

function Run-SlimServer($ps_server){
  $ps_fitnesse_client_task = $ps_server.AcceptTcpClientAsync()
  $ps_fitnesse_client = $ps_fitnesse_client_task.Result
  
  $ps_fitnesse_stream = $ps_fitnesse_client.GetStream()
  $ps_fitnesse_stream.ReadTimeout = $REQUEST_READ_TIMEOUT
  
  send_slim_version($ps_fitnesse_stream)
  $ps_fitnesse_client.Client.Poll(-1, [System.Net.Sockets.SelectMode]::SelectRead)
  while($ps_fitnesse_client.Connected -and "bye" -ne (process_message($ps_fitnesse_stream))){};
  $ps_fitnesse_client.Close()
}

function Run-RemoteServer($ps_server){
  Write-Log "waiting..."
  while($ps_fitnesse_client = $ps_server.AcceptTcpClient()){
    Write-Log "accepted!"
    $ps_fitnesse_stream = $ps_fitnesse_client.GetStream()
    $ps_fitnesse_stream.ReadTimeout = $REQUEST_READ_TIMEOUT
    
    process_message_ignore_remote($ps_fitnesse_stream)
    $ps_fitnesse_stream.Close()
    $ps_fitnesse_client.Close()
    Write-Log "waiting..."
  }
}

function Write-Log (){
  $timestamp = Get-Date -f "dd.MM.yy HH:mm:ss.fff"
  Write-Host $timestamp"`t"$args
}

Write-Log "========== Starting SLIM $Mode on Port $Port =========="

$ps_server = New-Object System.Net.Sockets.TcpListener('0.0.0.0', $Port)
$ps_server.Start()

if($Mode -eq "runner"){
  $scriptPath = split-path -parent $MyInvocation.MyCommand.Definition
  . $scriptPath\client.ps1
  Run-SlimServer $ps_server
}
else{ 
    Run-RemoteServer $ps_server 
}
$ps_server.Stop()
