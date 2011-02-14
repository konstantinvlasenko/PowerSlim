function script:process_table_remotely($computer, $fitnesse){
	$c = New-Object System.Net.Sockets.TcpClient($computer, 35)
	$remoteserver = $c.GetStream()
	$remoteserver.Write($slimbuffer, 0, $slimbuffersize)
	read_message($remoteserver)
	$fitnesse.Write($slimbuffer, 0, $slimbuffersize)
	$remoteserver.Close()         
    $client.Close() 
}

