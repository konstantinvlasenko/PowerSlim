######################################################################################
#The latest source code is available at http://github.com/konstantinvlasenko/PowerSlim
#Copyright 2011 by the author(s). All rights reserved
######################################################################################
$slimver = "Slim -- V0.3`n"
$slimnull = "000004:null:"
$slimvoid = "/__VOID__/"
$slimexception = "__EXCEPTION__:"
$slimsymbols = new-Object 'system.collections.generic.dictionary[string,object]'
$slimbuffer = new-object byte[] 102400
$slimbuffersize = 0

function Get-SlimTable($slimchunk){
	$exp = $slimchunk -replace "'","''" -replace "000000::","000000:blank:" -replace "(?S):\d{6}:([^\[].*?)(?=(:\d{6}|:\]))",',''$1''' -replace ":\d{6}:", "," -replace ":\]", ")" -replace "\[\d{6},", "(" -replace "'blank'", "''"
	iex $exp
}

function Test-OneRowTable($table){
	!($table[0] -is [array])
}

function Test-RemoteTable($table){
	"Remote".Equals($table[0][3],[System.StringComparison]::OrdinalIgnoreCase)
}

function SlimException-NoClass($class){
	$slimexception + "NO_CLASS " + $class
}

new-alias noclass SlimException-NoClass

function Get-SlimLength($obj){
	if($obj -is [array]){
		$obj.Count.ToString("d6")
	}
	else{
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

function PropertyTo-Slim($obj,$prop){
	$slimview = "[000002:" + (slimlen $prop) + ":" + $prop+ ":"
	if($($obj.$prop) -eq $null -or $($obj.$prop) -is [system.array]){
		$slimview += $slimnull + "]"
	}
	else{
		$slimview += (slimlen $($obj.$prop)) + ":" + $($obj.$prop).ToString() + ":]"
	}
	(slimlen $slimview) + ":" + $slimview + ":"
}

function ConvertTo-Object($hashtable){
   $object = New-Object PSObject
   $hashtable.GetEnumerator() | % { Add-Member -inputObject $object -memberType NoteProperty -name $_.Name -value $_.Value }
   $object
}

function ConvertTo-SimpleObject($obj){
   $object = New-Object PSObject
   Add-Member -inputObject $object -memberType NoteProperty -name "Value" -value $obj.ToString()
   $object
}

function ResultTo-List($list){
	if($list -eq $null){
		$slimvoid
	}
	elseif ($list -is [array]){
		$result = "[" + (slimlen $list) + ":"
		foreach ($obj in $list){
			if($obj -is [hashtable]){
				$obj = ConvertTo-Object $obj
			}
			if($obj -is [string] -or $obj -is [int]){
				$obj = ConvertTo-SimpleObject $obj
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
	if($slimsymbols.Count){$slimsymbols.Keys | ? {!(Test-Path variable:$_)} | ? {!($s -match "\`$$_\s*=")} | % {$s=$s -replace "\`$$_",$slimsymbols[$_] }}
	$s = [string]::Format( $fmt, $s)
	if($s.StartsWith('function',$true,$null)){Set-Variable -Name Script__ -Value $s -Scope Global}
	else{Set-Variable -Name Script__ -Value ($s -replace '\$(\w+)(?=\s*=)','$global:$1') -Scope Global}
}

function make($ins){
	if("Remote".Equals($ins[3],[System.StringComparison]::OrdinalIgnoreCase)){
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
	$msg = get_message($stream)
	$msg
	if(ischunk($msg)){
		$global:QueryFormat__ = $global:EvalFormat__ = "{0}"
		$table = Get-SlimTable $msg
				
		if(Test-OneRowTable $table){$results = Process-Instruction $table}
		else{
			if(Test-RemoteTable $table){process_table_remotely $table[0][4] $stream; return}
			else{$results = $table | % { Process-Instruction $_ }}
		}
		
		$send = [text.encoding]::utf8.getbytes((pack_results $results))
		$stream.Write($send, 0, $send.Length)
	}
}

function process_message_ignore_remote($stream){
	$msg = get_message($stream)
	if(ischunk($msg)){
		$global:QueryFormat__ = $global:EvalFormat__ = "{0}"
		$table = Get-SlimTable $msg
		
		$results = $table | % { Process-Instruction $_ }
		$send = [text.encoding]::utf8.getbytes((pack_results $results))
		$stream.Write($send, 0, $send.Length)
	}
}


function Run-SlimServer($port){
	$server = New-Object System.Net.Sockets.TcpListener($port)
	$server.Start()

	$c = $server.AcceptTcpClient()
	$fitnesse = $c.GetStream()
	send_slim_version($fitnesse)
	$c.Client.Poll(-1, [System.Net.Sockets.SelectMode]::SelectRead)
	while("bye" -ne (process_message($fitnesse))){};
	$c.Close()
	$server.Stop()
}

function Run-RemoteServer($port){
	$server = New-Object System.Net.Sockets.TcpListener($port)
	$server.Start()
	while($c = $server.AcceptTcpClient()){
		$slimserver = $c.GetStream()
		process_message_ignore_remote($slimserver)
		$slimserver.Close()
		$c.Close()
	}

	$server.Stop()
}

if(!$args[1]){Run-SlimServer $args[0]}
else{Run-RemoteServer $args[0]}