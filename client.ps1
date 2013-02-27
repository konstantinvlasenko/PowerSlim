function Get-RemoteSlimSymbols($inputTable)
{
  $__pattern__ = '(?<id>scriptTable_\d+_\d+):\d{6}:callAndAssign:\d{6}:(?<name>\w+):\d{6}:'
  $inputTable | select-string $__pattern__ -allmatches | % {$_.matches} | % {@{id=$_.Groups[1].Value;name=$_.Groups[2].Value}}
}

function PowerSlim-SendTable($ps_computer, $ps_port, $buffer, $length ) {
  "[$ps_computer $ps_port] Connecting..." | Out-Default
  $ps_client = new-Object System.Net.Sockets.TcpClient
  $ps_connect = $ps_client.BeginConnect($ps_computer,$ps_port,$null,$null)  
  $ps_wait = $ps_connect.AsyncWaitHandle.WaitOne(5000)  
  if(!$ps_wait) {   
    $ps_client.Close()   
    throw "[$ps_computer $ps_port] Connection Timeout"   
  } else {   
    $ps_client.EndConnect($ps_connect) | Out-Null
    "[$ps_computer $ps_port] Connected!" | Out-Default
    $remoteserver = $ps_client.GetStream()
    $remoteserver.Write($buffer, 0, $length)
    get_message($remoteserver)
    $remoteserver.Close()
    $ps_client.Close() 
  }
}

function script:process_table_remotely($ps_table, $ps_fitnesse){

    try {

      $originalslimbuffer = $slimbuffer.Clone()
      $originalslimbuffersize = $slimbuffersize

      $result = new-Object 'system.collections.generic.dictionary[string,object]'

      foreach($t in $targets){ 

          $ps_computer, $ps_port = $t.split(':')

          if($ps_computer.StartsWith('$')){
              $ps_computer = $slimsymbols[$ps_computer.Substring(1)]
          }

          if($ps_port -eq $null){$ps_port = 35};
                
          if($slimsymbols.Count -ne 0){
            $list = @($slimsymbols.GetEnumerator() | % {$_})
            $tr = "[" + (slimlen $list) + ":"

            foreach ($obj in $list){
                                
                $itemstr = "[" +  (6).ToString("d6") + ":"

                $itemstr += (slimlen 'scriptTable_0_0') + ":scriptTable_0_0:" + (slimlen 'callAndAssign') + ":callAndAssign:"
                $itemstr += (slimlen $obj.Key) + ":$($obj.Key):" + (slimlen 'scriptTableActor') + ":scriptTableActor:"
                $itemstr += (slimlen 'eval') + ":eval:"

                $itemstr +=  (($obj.Value.Length + 2).ToString("d6")) + ":'$($obj.Value)':"
    
                $itemstr += "]"
          
                $tr += (slimlen $itemstr) + ":" + $itemstr + ":"
            } 

            $tr += "]"
            
            $s2 = [text.encoding]::utf8.getbytes($tr).Length.ToString("d6") + ":" + $tr                     
            $s2 = [text.encoding]::utf8.getbytes($s2)

            PowerSlim-SendTable $ps_computer $ps_port $s2 $s2.Length | out-Null
          }
             
          $result[$ps_computer] = PowerSlim-SendTable $ps_computer $ps_port $originalslimbuffer $originalslimbuffersize
          #backward symbols sharing
          foreach($symbol in Get-RemoteSlimSymbols([text.encoding]::utf8.getstring($originalslimbuffer, 0, $originalslimbuffersize))) {
            $__pattern__ = "$($symbol.id):\d{6}:(?<value>.+?):\]"
            $slimsymbols[$symbol.name] = $result[$ps_computer] | select-string $__pattern__ | % {$_.matches} | % {$_.Groups[1].Value}
          }
      }

      #if($result.Count -eq 1){
      $ps_fitnesse.Write($slimbuffer, 0, $slimbuffersize)
      #}

    }
    catch {
      $_.Exception.Message | out-default
      $send = '[000002:' + (slimlen $ps_table[0][0]) + ':' + $ps_table[0][0] + ':' + (slimlen "__EXCEPTION__:ABORT_SLIM_TEST:message:<<$($_.Exception.Message)>>") + ':' + "__EXCEPTION__:ABORT_SLIM_TEST:message:<<$($_.Exception.Message)>>" + ':]'
      $send = (slimlen $send) + ":" + $send + ":"
      $send = [text.encoding]::utf8.getbytes((pack_results $send))
      $ps_fitnesse.Write($send, 0, $send.Length)
    }
}

function script:Test-TcpPort($ps_computer, $ps_port)
{   
    ###############################################################
    # This works
    # But performance is to slow due to job nature!
    #
    # $ErrorActionPreference = 'SilentlyContinue'
    # Start-Job -ScriptBlock {
      # $ps_client = New-Object System.Net.Sockets.TcpClient($args)
      # if($ps_client) { 
        # $ps_client.Connected
        # $ps_client.Close()
      # }else{ $false }
    # } -ArgumentList $ps_computer,$ps_port | wait-job | Receive-Job
    
    $ErrorActionPreference = 'SilentlyContinue'
    $s = new-object Net.Sockets.TcpClient
    $s.Connect($ps_remotehost, $ps_port)
    if ($s.Connected) {
        $s.Close()
        return $true
    }
    return $false
}

function script:Wait-RemoteServer($ps_remotehost)
{
    while(!(Test-TcpPort $ps_remotehost 35)){sleep 10}
}
