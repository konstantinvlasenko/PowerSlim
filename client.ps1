function script:process_table_remotely($table, $fitnesse){
	$computers = $table[0][4].Split(',')
	try {
		$result = new-Object 'system.collections.generic.dictionary[string,object]'
		foreach($computer in $computers){
			$c = New-Object System.Net.Sockets.TcpClient($computer, 35)
			$remoteserver = $c.GetStream()
			$remoteserver.Write($slimbuffer, 0, $slimbuffersize)
			
			$t= get_message($remoteserver)
			$t | Out-Default
			$result[$computer] = Get-SlimTable($t)
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



