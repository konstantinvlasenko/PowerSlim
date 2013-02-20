#
# "THE BEER-WARE LICENSE" (Revision 42):
# <konstantin.vlasenko@gmail.com> wrote this file. As long as you retain this notice
# you can do whatever you want with this stuff. If we meet some day, and you
# think this stuff is worth it, you can buy me a beer in return.
#
$slimver = "Slim -- V0.3`n"
$slimnull = "000004:null:"
#$slimvoid = "/__VOID__/"
$slimvoid = ""
$slimexception = "__EXCEPTION__:"
$slimsymbols = new-Object 'system.collections.generic.dictionary[string,object]'
$slimbuffer = new-object byte[] 102400
$slimbuffersize = 0

function Get-SlimTable($slimchunk){
  $exp = $slimchunk -replace "'","''" -replace "000000::","000000:blank:"  -replace "(?S):\d{6}:(.*?)(?=(:\d{6}:|:\]))",',''$1''' -replace "'(\[\d{6})'", '$1' -replace ":\d{6}:", "," -replace ":\]", ")" -replace "\[\d{6},", "(" -replace "'blank'", "''"
  iex $exp
}

function Test-OneRowTable($table){
  !($table[0] -is [array])
}

function SlimException-NoClass($class){
  $slimexception + "NO_CLASS " + $class
}

new-alias noclass SlimException-NoClass

function Get-SlimLength($obj){
  if($obj -is [array]){
    $obj.Count.ToString("d6")
  }
  elseif($obj -is 'system.collections.generic.keyvaluepair[string,object]'){
    (1).ToString("d6")
  }
  else {
    $obj.ToString().Length.ToString("d6")
  }
}
new-alias slimlen Get-SlimLength

function ischunk($msg){
  $msg.StartsWith('[') -and $msg.EndsWith(']')
}

function send_slim_version($stream){
  $version = [text.encoding]::ascii.getbytes($slimver)
  $stream.Write($version, 0, $version.Length)
}

function get_message_length($stream){
  $stream.Read($slimbuffer, 0, 7) | out-null
  $global:slimbuffersize = [int][text.encoding]::utf8.getstring($slimbuffer, 0, 6) + 7
  $slimbuffersize - 7
}

function read_message($stream){
  $size = get_message_length($stream)
  $offset = 0
  while($offset -lt $size){$offset += $stream.Read($slimbuffer, $offset + 7, $size)}
}

function get_message($stream){
  read_message($stream)
  [text.encoding]::utf8.getstring($slimbuffer, 7, $slimbuffersize - 7)
}

function ObjectTo-Slim($obj){
  $slimview = "[000002:" + (slimlen $prop) + ":" + $prop+ ":"
  if($($obj.$prop) -eq $null -or $($obj.$prop) -is [system.array]){
    $slimview += $slimnull + "]"
  }
  else{
    $slimview += (slimlen $($obj.$prop)) + ":" + $($obj.$prop).ToString() + ":]"
  }
  (slimlen $slimview) + ":" + $slimview + ":"
}

function ConvertTo-Json20([object] $item)
{
    add-type -assembly system.web.extensions
    $js=new-object system.web.script.serialization.javascriptSerializer
    return $js.Serialize($item) 
}

function PropertyTo-Slim($obj,$prop){
  $slimview = "[000002:" + (slimlen $prop) + ":" + $prop+ ":"
  if($($obj.$prop) -eq $null){
    $slimview += $slimnull + "]"
  }
  elseif($($obj.$prop) -is [system.array] -or $($obj.$prop) -is [psobject]){
    if ($Host.Version.Major -eq 3) { $slimview += (ConvertTo-Json -Compress $($obj.$prop)) |% {(slimlen $_) + ":" + $_.ToString() + ":]"} }
        else { $slimview += ConvertTo-JSON20 ($obj.$prop) |% {(slimlen $_) + ":" + $_.ToString() + ":]"} }        
  }
  else{
    $slimview += (slimlen $($obj.$prop)) + ":" + $($obj.$prop).ToString() + ":]"
  }
  (slimlen $slimview) + ":" + $slimview + ":"
}

function Convert-Hashtable-2Object($hashtable){
   $object = New-Object PSObject
   $hashtable.GetEnumerator() | % { Add-Member -inputObject $object -memberType NoteProperty -name $_.Name -value $_.Value }
   Add-Member -inputObject $object -memberType NoteProperty -name "COMPUTERNAME" -value $env:COMPUTERNAME
   $object
}

function Convert-KeyValuePair-2Object($kvp){
   $obj = New-Object PSObject -Property @{ Key=$kvp.Key; Value=$kvp.Value.ToString(); COMPUTERNAME=$env:COMPUTERNAME}
   $obj
}

function ConvertTo-SimpleObject($obj){
   $object = New-Object PSObject
   Add-Member -inputObject $object -memberType NoteProperty -name "Value" -value $obj.ToString()
   Add-Member -inputObject $object -memberType NoteProperty -name "COMPUTERNAME" -value $env:COMPUTERNAME
   $object
}

function GetNullObject{
   $object = New-Object PSObject
   Add-Member -inputObject $object -memberType NoteProperty -name "Value" -value "Null"
   Add-Member -inputObject $object -memberType NoteProperty -name "COMPUTERNAME" -value $env:COMPUTERNAME
   $object
}

function isgenericdict($list){
	$list -is [array] -and $list.Count -eq 1 -and $list[0] -is 'system.collections.generic.dictionary[string,object]'
}

function ResultTo-List($list){
  if($null -eq $list){
    $slimvoid
  }
  elseif ($list -is [array]){
    if (isgenericdict $list){
      $list = $list[0].GetEnumerator() | % {$_}
      if($list -eq $null){
        $list = @() #emulate empty array
      }
    }	
    $result = "[" + (slimlen $list) + ":"
    foreach ($obj in $list){
      if($obj -is [hashtable]){
        $obj = Convert-Hashtable-2Object $obj
      }
      if($obj -is [string] -or $obj -is [int]){
        $obj = ConvertTo-SimpleObject $obj
      }
      if ($obj -is 'system.collections.generic.keyvaluepair[string,object]'){
        $obj = Convert-KeyValuePair-2Object $obj
      }
      if ($null -eq $obj){ 
        $obj = GetNullObject 
      }
      $fieldscount = ($obj  | gm -membertype Property, NoteProperty  | measure-object).Count
      $itemstr = "[" +  $fieldscount.ToString("d6") + ":"
      $obj  | gm -membertype Property, NoteProperty | % {$itemstr += PropertyTo-Slim $obj $_.Name }
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
    foreach ($obj in $res){
      $result += $obj.ToString()
      $result += ","
    }
    $result.TrimEnd(",")
  }
}

function Invoke-SlimCall($fnc){
  $error.clear()
  switch ($fnc){
    "query" {$result = ResultTo-List @(iex $Script__)}
    "eval" {$result = ResultTo-String (iex $Script__)}
    default {$result = $slimvoid}
  }
  $global:matches = $matches
  if($error[0] -ne $null){$error[0]}
  else{$result.TrimEnd("`r`n")}
}

function Set-Script($s, $fmt){
  if(!$s){ return }
  $s = $s -replace '</?pre>' #workaround fitnesse strange behavior
  if($slimsymbols.Count){$slimsymbols.Keys | ? {!(Test-Path variable:$_)} | ? {!($s -match "\`$$_\s*=")} | % {$s=$s -replace "\`$$_",$slimsymbols[$_] }}
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

function Invoke-SlimInstruction($ins){
  $ins[0]
  switch ($ins[1]){
    "import" {iex ". .\$($ins[2])"; "OK"; return}
    "make" {make $ins; Set-Script $ins[$ins.Count - 1] $QueryFormat__; return}
    "callAndAssign" {$symbol = $ins[2]; $ins = $ins[0,1 + 3 .. $ins.Count]}
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
  $t = measure-command {$result = Invoke-SlimCall $ins[3]}
  $Script__ + " : " + $t.TotalSeconds | Out-Default
  
  if($symbol){$slimsymbols[$symbol] = $result}
  $result
}

function Process-Instruction($ins){
  $result = Invoke-SlimInstruction $ins
  $s = '[000002:' + (slimlen $result[0]) + ':' + $result[0] + ':' + (slimlen $result[1]) + ':' + $result[1] + ':]'
  (slimlen $s) + ":" + $s + ":"

}

function pack_results($results){
  if($results -is [array]){
    $send = "[" + (slimlen $results) + ":"
    $results | % {$send += $_}
  }
  else{
    $send = "[000001:$results"
  }
  $send += "]"
  [text.encoding]::utf8.getbytes($send).Length.ToString("d6") + ":" + $send
}

function process_message($stream){
  if($stream.CanRead){
    $msg = get_message($stream)
    $msg
    if(ischunk($msg)){
      $global:QueryFormat__ = $global:EvalFormat__ = "{0}"
      $table = Get-SlimTable $msg
      if(Test-OneRowTable $table){
        if($table[0].StartsWith("scriptTable_") -or $table[0].StartsWith("queryTable_")){
          if("Remote" -eq $table[3])
          {
            $global:Remote = $true
            $global:targets = $null
            $global:targets = iex $table[4]
            if($global:targets -eq $null){
              $global:targets = $table[4].Split(',').Trim(', ')
            }
          }
          else
          {
            $global:Remote = $false
          }
        }
        if($Remote -eq $true){
          process_table_remotely $table $stream;
          return
          ##This prevetns to refactor this function
          ##There is shoudn't be return. The results should be send back here instead of inside the process_table_remotely function
        }
        else{
          $results = Process-Instruction $table
        }
      }
      else{
        if($table[0][0].StartsWith("scriptTable_") -or $table[0][0].StartsWith("queryTable_")){
          if("Remote" -eq $table[0][3])
          {
            $global:Remote = $true
            $global:targets = $null
            $global:targets = iex $table[0][4]
            if($global:targets -eq $null){
              $global:targets = $table[0][4].Split(',').Trim(', ')
            }
          }
          else{
            $global:Remote = $false
          }
        }
        if($Remote -eq $true){
          process_table_remotely $table $stream;
          return
        }
        else{
          $results = $table | % { Process-Instruction $_ }
        }
      }
    
      $send = [text.encoding]::utf8.getbytes((pack_results $results))
      $stream.Write($send, 0, $send.Length)
    }
  }else{"bye"}
}

function process_message_ignore_remote($stream){

  $msg = get_message($stream)

  if(ischunk($msg)){

    $global:QueryFormat__ = $global:EvalFormat__ = "{0}"
    $table = Get-SlimTable $msg

    if(Test-OneRowTable $table){ $results = Process-Instruction $table }
    else { $results = $table | % { Process-Instruction $_ } }

    $send = [text.encoding]::utf8.getbytes((pack_results $results))
    $stream.Write($send, 0, $send.Length)

  }
}


function Run-SlimServer($slimserver){
  $c = $slimserver.AcceptTcpClient()
  $fitnesse = $c.GetStream()
  send_slim_version($fitnesse)
  $c.Client.Poll(-1, [System.Net.Sockets.SelectMode]::SelectRead)
  while("bye" -ne (process_message($fitnesse))){};
  $c.Close()
}

function Run-RemoteServer($slimserver){
  "waiting..." | Out-Default
  while($c = $slimserver.AcceptTcpClient()){
    "accepted!" | Out-Default
    $fitnesse = $c.GetStream()
    process_message_ignore_remote($fitnesse)
    $fitnesse.Close()
    $c.Close()
    "waiting..." | Out-Default
  }
}

$_s_ = New-Object System.Net.Sockets.TcpListener($args[0])
$_s_.Start()

if(!$args[1]){
  . .\client.ps1
  Run-SlimServer $_s_
}
else{ Run-RemoteServer $_s_ }
$_s_.Stop()
