######################################################################################
#The latest source code is available at http://github.com/konstantinvlasenko/PowerSlim
#Copyright 2011 by the author(s). All rights reserved 
######################################################################################
$slimver = "Slim -- V0.1`n"
$slimnull = "000004:null:"
$slimvoid = "/__VOID__/"
$slimexception = "__EXCEPTION__:"

function Get-Instructions($slimchunk){
	$exp = $slimchunk -replace "'","''" -replace ":\d{6}:([^\[].*?)(?=(:\d{6}|:\]))",',''$1''' -replace ":\d{6}:", "," -replace ":\]", ")" -replace "\[\d{6},", "("
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

function get_message($stream){
	$b = new-object byte[] 4096
	$n = $stream.Read($b, 0, $b.Length)
	[text.encoding]::utf8.getstring($b, 7, $n-7)
}

function Invoke-SlimMake($ins){
	switch ($ins[3]){
		"Script" {Set-Variable -Name Script -Value $ins[4] -Scope Global; $ins[0], "OK"}
		default {$ins[0], (noclass $ins[3])}
	}	
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

function Invoke-SlimCall($ins){
	$result = $slimvoid
	if($ins[3] -eq "query"){
		$result = ResultTo-Slim @(iex $Script)
	}
	elseif($ins[3] -eq "eval"){
		$result = ResultTo-Slim (iex $ins[4])
	}
	$ins[0], $result
}

function Invoke-SlimInstruction($ins){
	switch ($ins[1]){
		"make" {Invoke-SlimMake $ins}
		"call" {Invoke-SlimCall $ins}
	}	
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
	#(slimlen $send) + ":" + $send
}

function process_message($stream){
	$msg = get_message($stream)
	if(ischunk($msg)){
		#$msg | Out-File c:\PowerSlim\slim.log
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

 