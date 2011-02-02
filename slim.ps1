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
######################################################################################
#
#
######################################################################################
function Set-PowerSlimRemoting{
	if("VMware.VimAutomation.Core".Equals($args[0],[System.StringComparison]::OrdinalIgnoreCase)){
		Set-Variable -Name PowerSlimRemoting__ -Value "VMware.VimAutomation.Core" -Scope Global
		Add-PSSnapin $PowerSlimRemoting__
		Set-Variable -Name Host__ -Value $args[1] -Scope Global
		Set-Variable -Name HostUser__ -Value $args[2] -Scope Global
		Set-Variable -Name HostPswd__ -Value $args[3] -Scope Global
		Connect-VIServer -Server $Host__ -User $HostUser__ -Password $HostPswd__
	}
	else{
		"__EXCEPTION__:ABORT_SLIM_TEST:$($args[0]) is not supported"
	}
}
######################################################################################
#
#
######################################################################################
function Get-Instructions($slimchunk){
	$exp = $slimchunk -replace "'","''" -replace "000000::","000000:blank:" -replace "(?S):\d{6}:([^\[].*?)(?=(:\d{6}|:\]))",',''$1''' -replace ":\d{6}:", "," -replace ":\]", ")" -replace "\[\d{6},", "(" -replace "'blank'", "''"
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
	if("RScript".Equals($ins[3],[System.StringComparison]::OrdinalIgnoreCase)){
		if(!$PowerSlimRemoting__){ "__EXCEPTION__:call Set-PowerSlimRemoting before RScript"; return }
		if($PowerSlimRemoting__ -eq "VMware.VimAutomation.Core"){
			Set-Variable -Name QueryFormat__ -Value "Invoke-VMScript ""{0} | ConvertTo-CSV -NoTypeInformation"" (Get-VM $($ins[4])) -HostUser $HostUser__ -HostPassword '$HostPswd__' -GuestUser $($ins[5]) -GuestPassword '$($ins[6])' | ConvertFrom-CSV" -Scope Global
			Set-Variable -Name EvalFormat__ -Value "Invoke-VMScript ""{0}"" (Get-VM $($ins[4])) -HostUser $HostUser__ -HostPassword '$HostPswd__' -GuestUser $($ins[5]) -GuestPassword '$($ins[6])'" -Scope Global
		}
	}
	"OK"
}

function Invoke-SlimInstruction($ins){
	$ins[0]
	switch ($ins[1]){
		"import" {Add-PSSnapin $ins[2]; "OK"; return}
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
	if(ischunk($msg)){
		Set-Variable -Name QueryFormat__ -Value "{0}" -Scope Global
		Set-Variable -Name EvalFormat__ -Value "{0}" -Scope Global
		#$msg | Out-File c:\powerslim\slim.log -append
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

$server = New-Object System.Net.Sockets.TcpListener($args[0])
$server.Start()
$c = $server.AcceptTcpClient()
$stream = $c.GetStream()
send_slim_version($stream)
while("bye" -ne (process_message($stream))){};
$c.Close()
$server.Stop()

 