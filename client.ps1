function script:process_table_remotely($table, $fitnesse){
	$table | Out-Default
	$computer = $table[0][4]
	try {
		$c = New-Object System.Net.Sockets.TcpClient($computer, 35)
		$remoteserver = $c.GetStream()
		$remoteserver.Write($slimbuffer, 0, $slimbuffersize)
		read_message($remoteserver)
		$fitnesse.Write($slimbuffer, 0, $slimbuffersize)
		$remoteserver.Close()         
		$c.Close() 
	}
	catch [System.Exception] {
		$_.Exception.Message | Out-Default
		$send = '[000002:' + (slimlen $table[0][0]) + ':' + $table[0][0] + ':' + (slimlen $_.Exception.Message) + ':' + $_.Exception.Message + ':]'
		$send = (slimlen $send) + ":" + $send + ":"
		
				
		$send = [text.encoding]::utf8.getbytes((pack_results $send))
		$fitnesse.Write($send, 0, $send.Length)
	}
}



