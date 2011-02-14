function script:process_table_remotely($computer, $fitnesse){
	$c = New-Object System.Net.Sockets.TcpClient($computer, 35)
	if(!$?){
		$send = [text.encoding]::utf8.getbytes("run server")
		$fitnesse.Write($send, 0, $send.Length)
	}
	else{
		$remoteserver = $c.GetStream()
		$remoteserver.Write($slimbuffer, 0, $slimbuffersize)
		read_message($remoteserver)
		$fitnesse.Write($slimbuffer, 0, $slimbuffersize)
		$remoteserver.Close()         
		$c.Close() 
	}
}

