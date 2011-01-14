function Get-SlimLength($obj){
	if($obj -is [system.array]){
		$obj.Count.ToString("d6")
	}
	else{
		$obj.ToString().Length.ToString("d6")
	}
}
new-alias slimlen Get-SlimLength

function send_slim_version($stream){
	$version = [text.encoding]::ascii.getbytes("Slim -- V0.1`n")
	$stream.Write($version, 0, $version.Length)
}

function get_message($stream){
	$b = new-object byte[] 1024
	$n = $stream.Read($b, 0, $b.Length)
	[text.encoding]::utf8.getstring($b, 7, $n-7)
}

function ischunk($msg){
	$msg.StartsWith('[') -and $msg.EndsWith(']')
}

function Invoke-SlimMake($ins){
	switch ($ins[3]){
		"Script" {Set-Variable -Name Script -Value $ins[4] -Scope Global; $ins[0], "OK"}
		default {$ins[0], "__EXCEPTION__:NO_CLASS $($ins[3])"}
	}	
}

function PropertyTo-Slim($obj,$prop){
	$slimview = "[000002:" + slimlen $prop + ":" + $prop+ ":"
	if($($obj.$prop) -ne $null){
		$slimview += slimlen $($obj.$prop) + ":" + $($obj.$prop).ToString() + ":]"
	}
	else{
		$slimview += "000004:null:]"
	}
	slimlen $slimview + ":" + $slimview + ":"
}

function Invoke-SlimCall($ins){
	$result = "/__VOID__/"
	if($ins[3] -eq "query"){
		$list = @(Invoke-Expression $Script)
		$result = "[" + slimlen $list + ":"
		foreach ($obj in $list){  
			$fieldscount = ($obj  | gm -membertype property | measure-object).Count
			$itemstr = "[" +  slimlen $fieldscount + ":"
			$obj  | gm -membertype property | % {$itemstr += PropertyTo-Slim $obj $_.Name }
			$itemstr += "]"
			$result += slimlen $itemstr + ":" + $itemstr + ":"
		} 
		$result += "]"
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
	$s = '[000002:' + slimlen $result[0] + ':' + $result[0] + ':' + slimlen $result[1] + ':' + $result[1] + ':]'
	slimlen $s + ":" + $s + ":"

}

function Get-Instructions($msg){
	$exp = $msg -replace "\d{6}:", "" -replace ":\]", "]" -replace ":", "," -replace "\[", "@(" -replace "\]", ")" -replace "([^\(\)@,]+)", "'$&'"
	Invoke-Expression $exp
}

function pack_results($results){
	$send = "[" + slimlen $results + ":"
	$results | % {$send += $_}
	$send += "]"
	slimlen $send + ":" + $send
}

function process_message($stream){
	$msg = get_message($stream)
	if(ischunk($msg)){
		$results = Get-Instructions $msg | % { Process-Instruction $_ }
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
 