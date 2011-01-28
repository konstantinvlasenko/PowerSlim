######################################################################################
#The latest source code is available at http://github.com/konstantinvlasenko/PowerSlim
#Copyright 2011 by the author(s). All rights reserved
######################################################################################
$slimver = "Slim -- V0.3`n"
$slimnull = "000004:null:"
$slimvoid = "/__VOID__/"
$slimexception = "__EXCEPTION__:"
$slimbuffer = new-object byte[] 20480

function Get-Instructions($slimchunk){
	$exp = $slimchunk -replace "'","''" -replace "000000::","000000:blank:" -replace ":\d{6}:([^\[].*?)(?=(:\d{6}|:\]))",',''$1''' -replace ":\d{6}:", "," -replace ":\]", ")" -replace "\[\d{6},", "(" -replace "'blank'", "''"
	iex $exp
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
	$b = new-object byte[] 7
	$stream.Read($b, 0, $b.Length) | out-null
	[int][text.encoding]::utf8.getstring($b, 0, 6)
}

function get_message($stream){
	$size = get_message_length($stream)
	$offset = 0
	while($offset -lt $size){$offset += $stream.Read($slimbuffer, $offset, $size)}
	[text.encoding]::utf8.getstring($slimbuffer, 0, $size)
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
   Add-Member -inputObject $object -memberType NoteProperty -name $obj.GetType().Name -value $obj.ToString()
   $object
}

function ResultTo-Slim($list){
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

function Invoke-SlimCall($fnc){
	$error.clear()
	switch ($fnc){
		"query" {$result = @(iex $Script__)}
		"eval" {$result = iex $Script__}
		default {$result = $slimvoid}
	}
	if($error[0] -ne $null){$error[0]}
	else{ResultTo-Slim $result}
}

function Invoke-SlimInstruction($ins){
	$ins[0]
	switch ($ins[1]){
		"import" {Add-PSSnapin $ins[2]; "OK"; break;}
		"make" {Set-Script $ins[4]; "OK"; break}
		"callAndAssign" {$symbol = $ins[2]; $ins = $ins[0,1 + 3 .. $ins.Count]}
	}
	if($ins[3] -ne "query" -and $ins[3] -ne "table"){
		Set-Script $ins[4]
	}

	$result = Invoke-SlimCall $ins[3]
	if($symbol){$global:symbols += @{$symbol=$result}}
	$result
}

function Set-Script($s){
	if($symbols){$symbols.Keys | % {$s=$s -replace "\`$$_",$symbols.item($_) }}
	Set-Variable -Name Script__ -Value ($s -replace '\$(\w+)(?=\s*=)','$global:$1') -Scope Global
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
	if(ischunk($msg)){
		#$msg | Out-File c:\slim.log
		$ins = Get-Instructions $msg
		
		if($ins[0] -is [array]){
			$results = $ins | % { Process-Instruction $_ }
		}
		else{
			$results = Process-Instruction $ins
		}
		$send = [text.encoding]::utf8.getbytes((pack_results $results))
		$stream.Write($send, 0, $send.Length)
	}
	$msg
}
$s = New-Object System.Net.Sockets.TcpListener($args[0])
$s.Start()
$c = $s.AcceptTcpClient()
$stream = $c.GetStream()
send_slim_version($stream)
while("bye" -ne (process_message($stream))){};
$c.Close()
$s.Stop()

 