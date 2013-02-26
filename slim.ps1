##########################
# PowerSlim (Revision 46)#
##########################
$slimver = "Slim -- V0.3`n"
$slimnull = "000004:null:"
#$slimvoid = "/__VOID__/"
$slimvoid = ""
$slimexception = "__EXCEPTION__:"
$slimsymbols = new-Object 'system.collections.generic.dictionary[string,object]'
$slimbuffer = new-object byte[] 102400
$slimbuffersize = 0

#$VerbosePreference="Continue"

function Get-SlimTable($slimchunk){

  $ps_exp = $slimchunk -replace "'","''" -replace "000000::","000000:blank:"  -replace "(?S):\d{6}:(.*?)(?=(:\d{6}:|:\]))",',''$1''' -replace "'(\[\d{6})'", '$1' -replace ":\d{6}:", "," -replace ":\]", ")" -replace "\[\d{6},", "(" -replace "'blank'", "''"

  Write-Verbose $ps_exp

  $global:ps_table = iex $ps_exp
}


function Test-OneRowTable($ps_table){
  !($ps_table[0] -is [array])
}

function SlimException-NoClass($ps_class){
  $slimexception + "NO_CLASS " + $ps_class
}

new-alias noclass SlimException-NoClass

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

function get_message_length($ps_stream){
  $ps_stream.Read($slimbuffer, 0, 7) | out-null
  $global:slimbuffersize = [int][text.encoding]::utf8.getstring($slimbuffer, 0, 6) + 7
  $slimbuffersize - 7
}

function read_message($ps_stream){
  $ps_size = get_message_length($ps_stream)
  $offset = 0
  while($offset -lt $ps_size){
    
    $error.clear()
    $offset += $ps_stream.Read($slimbuffer, $offset + 7, $ps_size)

    #if ($error -or !$ps_stream.Socket.Connected) {break}
    if ($error -or !$ps_stream.Socket.Connected) {break}

  }
}

function get_message($ps_stream){
  read_message($ps_stream)
  [text.encoding]::utf8.getstring($slimbuffer, 7, $slimbuffersize - 7)
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
  elseif($($ps_obj.$ps_prop) -is [system.array] -or $($ps_obj.$ps_prop) -is [psobject]){
    if ($Host.Version.Major -eq 3) { $slimview += (ConvertTo-Json -Compress $($ps_obj.$ps_prop)) |% {(slimlen $_) + ":" + $_.ToString() + ":]"} }
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
   Add-Member -inputObject $ps_object -memberType NoteProperty -name "COMPUTERNAME" -value $env:COMPUTERNAME
   $ps_object
}

function Convert-KeyValuePair-2Object($kvp){
   $ps_obj = New-Object PSObject -Property @{ Key=$kvp.Key; Value=$kvp.Value.ToString(); COMPUTERNAME=$env:COMPUTERNAME}
   $ps_obj
}

function ConvertTo($ps_str) {

  $ps_object = New-Object PSObject

  Add-Member -inputObject $ps_object -memberType NoteProperty -name "Value" -value $ps_str
  Add-Member -inputObject $ps_object -memberType NoteProperty -name "COMPUTERNAME" -value $env:COMPUTERNAME

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


function Invoke-SlimCall($fnc){
  switch ($fnc){
    {($_ -eq "query") -or ($_ -eq "eval")} {iex $Script__}
    default { 
      if ((Table-Type) -eq "ScriptTableActor") { "please use eval" }
      else{ $slimvoid }
    }
  }
  $global:matches = $matches
}

function Set-Script($s, $fmt){
  if(!$s){ return }
  $s = $s -replace '<table class="hash_table">\r\n', '@{' -replace '</table>','}' -replace '\t*<tr class="hash_row">\r\n','' -replace '\t*</tr>\r\n','' -replace '\t*<td class="hash_key">(.*)</td>\r\n', '''$1''=' -replace '\t*<td class="hash_value">(.*)</td>\r\n','''$1'';'
  $s = $s -replace '</?pre>' #workaround fitnesse strange behavior
  if($slimsymbols.Count){$slimsymbols.Keys | ? {!($s -match "\`$$_\s*=")} | ? {$slimsymbols[$_] -is [string] } | % {$s=$s -replace "\`$$_",$slimsymbols[$_] }}
  if($slimsymbols.Count){$slimsymbols.Keys | % { Set-Variable -Name $_ -Value $slimsymbols[$_] -Scope Global}}
  $s = [string]::Format( $fmt, $s)
  if($s.StartsWith('function',$true,$null)){Set-Variable -Name Script__ -Value ($s -replace 'function\s+(.+)(?=\()','function global:$1') -Scope Global}
  else{Set-Variable -Name Script__ -Value ($s -replace '\$(\w+)(?=\s*=)','$global:$1') -Scope Global}
}

function make($ins){
  if("ESXI".Equals($ins[3],[System.StringComparison]::OrdinalIgnoreCase)){
    $global:QueryFormat__ = Get-QueryFormat $ins
    $global:EvalFormat__ = Get-EvalFormat $ins
  }
  "OK"
}

function Id() {$global:ps_row[0]}
function Operation() {$global:ps_row[1]}
function Module() {$global:ps_row[2]}
function Table-Type() {$global:ps_row[2]}

function Invoke-SlimInstruction(){

  $ins = $global:ps_row

  (Id)

  switch (Operation){

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

    "call" { 
      if($ins[2].StartsWith('decisionTable')){
        if($ins[3] -match ('table|beginTable|reset|endTable')){
          "/__VOID__/"
          return
        }elseif($ins[3][0..2] -join '' -eq 'set'){
          iex "`$global:$($ins[3].Substring(3))='$($ins[4])'"
          "/__VOID__/"
          return
        }elseif($ins[3] -eq 'execute'){
          $global:decision_result = iex "$Script__ 2>&1"
          $slimvoid
          #$global:decision_result
          return
        }else{
          if($ins[3] -ne 'Result'){
            "Not Implemented"
          }else{
            $global:decision_result
          }
          return
        }
      }
    }
  }
  
  if($ins[3] -ne "query" -and $ins[3] -ne "table"){
    Set-Script $ins[4] $EvalFormat__
  }
  
  $error.clear()
  $t = measure-command { $result = Invoke-SlimCall $ins[3] }
  $Script__ + " : " + $t.TotalSeconds | Out-Default
  if($error[0] -ne $null){ return $error[0] }
  #if($null -eq $result){ return $slimvoid }
  if($symbol){ $slimsymbols[$symbol] = $result }
  
  $error.clear()
  switch ($ins[3]){
    "query" {
      if(($null -eq $result) -or ($result -is 'system.collections.generic.dictionary[string,object]' -and  $result.Count -eq 0)){ 
        $result = ResultTo-List @()
      }
      else{
        $result = ResultTo-List @($result)
      }
    }
    "eval" {$result = ResultTo-String $result}
  }
  if($error[0] -ne $null){ return $error[0] }
  else { $result.TrimEnd("`r`n") }
}

function Process-Instruction($ins){

  $global:ps_row = $ins
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
        $global:Remote = $false
      }

  }

}

function set_remote_targets($ps_cell) {

  $global:Remote = $true
  $global:targets = $null

  $global:targets = iex $ps_cell
  
  if($global:targets -eq $null){
    $global:targets = $ps_cell.Split(",") | %{$_.Trim(", ")}
  }

}

function process_table() {

  if(Test-OneRowTable $global:ps_table){ $ps_results = Process-Instruction $global:ps_table }
  else { $ps_results = $global:ps_table | % { Process-Instruction $_ } }

  $ps_results

}

function process_message($ps_stream){

  if( ! $ps_stream.CanRead ){ return "buy" }

  $ps_msg = get_message($ps_stream)
  $ps_msg

  if( !(ischunk $ps_msg) ){ return }

  $global:QueryFormat__ = $global:EvalFormat__ = "{0}"
  Get-SlimTable $ps_msg

  check_remote($global:ps_table)

  if($Remote -eq $true){
    process_table_remotely $global:ps_table $ps_stream;
    return
  }
  
  $ps_results = process_table

  $ps_send = [text.encoding]::utf8.getbytes((pack_results $ps_results))
  $ps_stream.Write($ps_send, 0, $ps_send.Length)
  
}

function process_message_ignore_remote($ps_stream){

  $ps_msg = get_message($ps_stream)

  if(ischunk($ps_msg)){

    $global:QueryFormat__ = $global:EvalFormat__ = "{0}"
    $ps_table = Get-SlimTable $ps_msg

    $ps_results = process_table

    $ps_send = [text.encoding]::utf8.getbytes((pack_results $ps_results))
    $ps_stream.Write($ps_send, 0, $ps_send.Length)

  }
}

function Run-SlimServer($ps_server){
  $ps_fitnesse_client = $ps_server.AcceptTcpClient()
  $ps_fitnesse_stream = $ps_fitnesse_client.GetStream()
  send_slim_version($ps_fitnesse_stream)
  $ps_fitnesse_client.Client.Poll(-1, [System.Net.Sockets.SelectMode]::SelectRead)
  while("bye" -ne (process_message($ps_fitnesse_stream))){};
  $ps_fitnesse_client.Close()
}

function Run-RemoteServer($ps_server){
  "waiting..." | Out-Default
  while($ps_fitnesse_client = $ps_server.AcceptTcpClient()){
    "accepted!" | Out-Default
    $ps_fitnesse_stream = $ps_fitnesse_client.GetStream()
    process_message_ignore_remote($ps_fitnesse_stream)
    $ps_fitnesse_stream.Close()
    $ps_fitnesse_client.Close()
    "waiting..." | Out-Default
  }
}

$ps_server = New-Object System.Net.Sockets.TcpListener($args[0])
$ps_server.Start()

if(!$args[1]){
  . .\client.ps1
  Run-SlimServer $ps_server
}
else{ Run-RemoteServer $ps_server }
$ps_server.Stop()
