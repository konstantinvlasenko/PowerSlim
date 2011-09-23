#
# "THE BEER-WARE LICENSE" (Revision 42):
# <konstantin.vlasenko@gmail.com> wrote this file. As long as you retain this notice
# you can do whatever you want with this stuff. If we meet some day, and you
# think this stuff is worth it, you can buy me a beer in return.
#
function script:process_table_remotely($table, $fitnesse){
	$targets = $table[0][4].Trim(',').Split(',')
	try {
		$originalslimbuffer = $slimbuffer.Clone()
		$originalslimbuffersize = $slimbuffersize
		$result = new-Object 'system.collections.generic.dictionary[string,object]'
		foreach($t in $targets){ 
			$computer, $port = $t.split(':')
			if($computer.StartsWith('$')){
				$computer = $slimsymbols[$computer.Substring(1)]
			}
			if($port -eq $null){$port = 35};
			$computer, $port | Out-Default
			$c = New-Object System.Net.Sockets.TcpClient($computer, $port)
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