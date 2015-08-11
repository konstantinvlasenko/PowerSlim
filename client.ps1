#
# "THE BEER-WARE LICENSE" (Revision 42):
# <konstantin.vlasenko@gmail.com> wrote this file. As long as you retain this notice
# you can do whatever you want with this stuff. If we meet some day, and you
# think this stuff is worth it, you can buy me a beer in return.
#

# the timeout for the Remote server is 1 hour
$REMOTE_SERVER_READ_TIMEOUT = 60*60*1000

function Get-RemoteSlimSymbols($inputTable)
{
  $__pattern__ = '(?<id>scriptTable_\d+_\d+):\d{6}:callAndAssign:\d{6}:(?<name>\w+):\d{6}:'
  $inputTable | select-string $__pattern__ -allmatches | % {$_.matches} | % {@{id=$_.Groups[1].Value;name=$_.Groups[2].Value}}
}

function script:process_table_remotely($ps_table, $ps_fitnesse){

    try {

      $originalslimbuffer = $ps_buf1 + $ps_buf2

      $result = new-Object 'system.collections.generic.dictionary[string,object]'

      foreach($t in $targets){ 

          $ps_computer, $ps_port = $t.split(':')

          if($ps_computer.StartsWith('$')){
              $ps_computer = $slimsymbols[$ps_computer.Substring(1)]
          }

          if($ps_port -eq $null){$ps_port = 35};

          Write-Verbose "Connecting to $ps_computer, $ps_port"
          
          if($slimsymbols.Count -ne 0){

              "Connecting to $ps_computer $ps_port" | Out-Default

              $ps_sumbols_client = New-Object System.Net.Sockets.TcpClient($ps_computer, $ps_port)
              $remoteserver = $ps_sumbols_client.GetStream()
              $remoteserver.ReadTimeout = $REMOTE_SERVER_READ_TIMEOUT

              "Connected" | Out-Default
                      
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

              $remoteserver.Write($s2, 0, $s2.Length)
              get_message($remoteserver)

          }

         $ps_client = New-Object System.Net.Sockets.TcpClient($ps_computer, $ps_port)
         $remoteserver = $ps_client.GetStream()
         $remoteserver.ReadTimeout = $REMOTE_SERVER_READ_TIMEOUT
    
         $remoteserver.Write($originalslimbuffer, 0, $originalslimbuffer.Length)
         $result[$ps_computer] = get_message($remoteserver)
    
          #backward symbols sharing
         foreach($symbol in Get-RemoteSlimSymbols([text.encoding]::utf8.getstring($originalslimbuffer, 0, $originalslimbuffer.Length))) {
            $__pattern__ = "$($symbol.id):\d{6}:(?<value>.+?):\]"
            $slimsymbols[$symbol.name] = $result[$ps_computer] | select-string $__pattern__ | % {$_.matches} | % {$_.Groups[1].Value}
         }
      
         $remoteserver.Close()         
         $ps_client.Close() 

      }

      #if($result.Count -eq 1){

      $res = $ps_buf1 + $ps_buf2
      $ps_fitnesse.Write($res, 0, $res.Length)

      #}

    }
    catch [System.Exception] {
        $send = '[000002:' + (slimlen $ps_table[0][0]) + ':' + $ps_table[0][0] + ':' + (slimlen "$slimexception$($_.Exception.Message)") + ':' + "$slimexception$($_.Exception.Message)" + ':]'
        $send = (slimlen $send) + ":" + $send + ":"
        $send = [text.encoding]::utf8.getbytes((pack_results $send))
        $ps_fitnesse.Write($send, 0, $send.Length)
    }
}

function script:Test-TcpPort($ps_remotehost, $ps_port)
{
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
