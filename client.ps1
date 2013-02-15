#
# "THE BEER-WARE LICENSE" (Revision 42):
# <konstantin.vlasenko@gmail.com> wrote this file. As long as you retain this notice
# you can do whatever you want with this stuff. If we meet some day, and you
# think this stuff is worth it, you can buy me a beer in return.
#
function Get-RemoteSlimSymbols($inputTable)
{
  $__pattern__ = '(?<id>scriptTable_\d_\d):\d{6}:callAndAssign:\d{6}:(?<name>\w*):\d{6}:'
  $inputTable | select-string $__pattern__ -allmatches | % {$_.matches} | % {@{id=$_.Groups[1].Value;name=$_.Groups[2].Value}}
}

function script:process_table_remotely($table, $fitnesse){

    #$targets = $table[0][4].Trim(',').Split(',')
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
            
            if($slimsymbols.Count -ne 0){

                $c = New-Object System.Net.Sockets.TcpClient($computer, $port)
                $remoteserver = $c.GetStream()
                        
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

                $tr | Out-Default 

                $remoteserver.Write($s2, 0, $s2.Length)
                get_message($remoteserver)

            }
      
           $c = New-Object System.Net.Sockets.TcpClient($computer, $port)
           $remoteserver = $c.GetStream()
      
           $remoteserver.Write($originalslimbuffer, 0, $originalslimbuffersize)
           $result[$computer] = get_message($remoteserver)
      
            #backward symbols sharing
           foreach($symbol in Get-RemoteSlimSymbols([text.encoding]::utf8.getstring($originalslimbuffer, 0, $originalslimbuffersize))) {
              $__pattern__ = "$($symbol.id):\d{6}:(?<value>\w*):\]"
              $slimsymbols[$symbol.name] = $result[$computer] | select-string $__pattern__ | % {$_.matches} | % {$_.Groups[1].Value}
           }
        
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
