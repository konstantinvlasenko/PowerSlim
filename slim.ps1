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
	$slimview = "[000002:" + $prop.Length.ToString("d6") + ":" + $prop+ ":"
	if($($obj.$prop) -ne $null){
		$slimview += $($obj.$prop).ToString().Length.ToString("d6") + ":" + $($obj.$prop).ToString() + ":]"
	}
	else{
		$slimview += "000004:null:]"
	}
	$slimview.Length.ToString("d6") + ":" + $slimview + ":"
}

function Invoke-SlimCall($ins){
	$result = "/__VOID__/"
	if($ins[3] -eq "query"){
		$list = @(Invoke-Expression $Script)
		$result = "[" + $list.Length.ToString("d6") + ":"
		foreach ($obj in $list){  
			$fieldscount = ($obj  | gm -membertype property | measure-object).Count
			$itemstr = "[" + $fieldscount.ToString("d6") + ":"
			$obj  | gm -membertype property | % {$itemstr += PropertyTo-Slim $obj $_.Name }
			$itemstr += "]"
			$result += $itemstr.Length.ToString("d6") + ":" + $itemstr + ":"
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
	$s = '[000002:' + $result[0].Length.ToString("d6") + ':' + $result[0] + ':' + $result[1].Length.ToString("d6") + ':' + $result[1] + ':]'
	$s.Length.ToString("d6") + ":" + $s + ":"

}

function Get-Instructions($msg){
	$exp = $msg -replace "\d{6}:", "" -replace ":\]", "]" -replace ":", "," -replace "\[", "@(" -replace "\]", ")" -replace "([^\(\)@,]+)", "'$&'"
	Invoke-Expression $exp
}

function pack_results($results){
	$send = "[" + $results.Length.ToString("d6") + ":"
	$results | % {$send += $_}
	$send += "]"
	$send.Length.ToString("d6") + ":" + $send
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
 