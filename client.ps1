function script:process_table_remotely($table, $fitnesse){
	$computers = $table[0][4].Trim(',').Split(',')
	try {
		$originalslimbuffer = $slimbuffer.Clone()
		$originalslimbuffersize = $slimbuffersize
		$result = new-Object 'system.collections.generic.dictionary[string,object]'
		foreach($computer in $computers){
			$computer | Out-Default
			$c = New-Object System.Net.Sockets.TcpClient($computer, 35)
			$remoteserver = $c.GetStream()
			$remoteserver.Write($originalslimbuffer, 0, $originalslimbuffersize)
			$result[$computer] = get_message($remoteserver)
			$remoteserver.Close()         
			$c.Close() 
		}
		#if($result.Count -eq 1){
		$fitnesse.Write($slimbuffer, 0, $slimbuffersize)
		#}
	}
	catch [System.Exception] {
		$send = '[000002:' + (slimlen $table[0][0]) + ':' + $table[0][0] + ':' + (slimlen "$slimexception$($_.Exception.Message)") + ':' + "$slimexception$($_.Exception.Message)" + ':]'
		$send = (slimlen $send) + ":" + $send + ":"
		$send = [text.encoding]::utf8.getbytes((pack_results $send))
		$fitnesse.Write($send, 0, $send.Length)
	}
}

function script:Test-TcpPort($remotehost, $port)
{
	$ErrorActionPreference = 'SilentlyContinue'
	$s = new-object Net.Sockets.TcpClient
	$s.Connect($remotehost, $port)
	if ($s.Connected) {
		$s.Close()
		return $true
	}
	return $false
}

function script:Wait-RemoteServer($remotehost)
{
	while(!(Test-TcpPort $remotehost 35)){sleep 10}
}