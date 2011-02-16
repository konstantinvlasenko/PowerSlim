function script:process_table_remotely($table, $fitnesse){
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
		$send = '[000002:' + (slimlen $table[0][0]) + ':' + $table[0][0] + ':' + (slimlen "$slimexception$($_.Exception.Message)") + ':' + "$slimexception$($_.Exception.Message)" + ':]'
		$send = (slimlen $send) + ":" + $send + ":"
		$send = [text.encoding]::utf8.getbytes((pack_results $send))
		$fitnesse.Write($send, 0, $send.Length)
	}
}



