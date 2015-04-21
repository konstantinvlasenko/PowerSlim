##########################
# PowerSlim (Revision 47)#
##########################

# "THE BEER-WARE LICENSE" (Revision 42):
# <konstantin.vlasenko@gmail.com> wrote this file. As long as you retain this notice
# you can do whatever you want with this stuff. If we meet some day, and you
# think this stuff is worth it, you can buy me a beer in return.

$slimver = "Slim -- V0.3`n"
$slimvoid = ''
$slimexception = '__EXCEPTION__'
$slimsymbols = New-Object -TypeName 'system.collections.generic.dictionary[string,object]'

#$VerbosePreference="Continue"

# Support for slow connection.
# Idea is that the client should send data, so the stream is in the read mode. We can wait 10 seconds or more?
$REQUEST_READ_TIMEOUT = 10000

#  Timeout for the Remote server is 1 hour
$REMOTE_SERVER_READ_TIMEOUT = 60*60*1000

$script:SLIM_ABORT_TEST = $false
$script:SLIM_ABORT_SUITE = $false
$script:POWERSLIM_PATH = $MyInvocation.MyCommand.Path
$script:POWERSLIM_HOME = Split-Path -Parent -Path $MyInvocation.MyCommand.Path

function Write-Log ($message)
{
    $timestamp = Get-Date -Format 'HH:mm:ss.fff'
    Write-Host "$timestamp $message"
}

function Get-RemoteSlimSymbols($inputTable)
{
    $__pattern__ = '(?<id>scriptTable_\d+_\d+):\d{6}:callAndAssign:\d{6}:(?<name>\w+):\d{6}:'
    $inputTable | Select-String $__pattern__ -AllMatches | % {
        $_.matches
    } | % {
        @{
            id   = $_.Groups[1].Value
            name = $_.Groups[2].Value
        }
    }
}

function process_table_remotely($ps_table, $ps_fitnesse)
{
    try 
    {
        $originalslimbuffer = $ps_buf1 + $ps_buf2

        $result = New-Object 'system.collections.generic.dictionary[string,object]'

        foreach($t in $targets)
        {
            $ps_computer, $ps_port = $t.split(':')

            if($ps_computer.StartsWith('$'))
            {
                $ps_computer = $slimsymbols[$ps_computer.Substring(1)]
            }

            if($ps_port -eq $null)
            {
                $ps_port = 35
            }           
          
            if($slimsymbols.Count -ne 0)
            {
                Write-Log "Connecting to $($ps_computer):$ps_port"

                $ps_sumbols_client = New-Object -TypeName System.Net.Sockets.TcpClient -ArgumentList ($ps_computer, $ps_port)
                $remoteserver = $ps_sumbols_client.GetStream()
                $remoteserver.ReadTimeout = $REMOTE_SERVER_READ_TIMEOUT
                      
                $list = @($slimsymbols.GetEnumerator() | % { $_ })
                $tr = '[' + (slimlen $list) + ':'

                foreach ($obj in $list)
                {
                    $itemstr = '[' +  (6).ToString('d6') + ':'

                    $itemstr += (slimlen 'scriptTable_0_0') + ':scriptTable_0_0:' + (slimlen 'callAndAssign') + ':callAndAssign:'
                    $itemstr += (slimlen $obj.Key) + ":$($obj.Key):" + (slimlen 'scriptTableActor') + ':scriptTableActor:'
                    $itemstr += (slimlen 'eval') + ':eval:'

                    $itemstr += (($obj.Value.Length + 2).ToString('d6')) + ":'$($obj.Value)':"
    
                    $itemstr += ']'
          
                    $tr += (slimlen $itemstr) + ':' + $itemstr + ':'
                } 

                $tr += ']'
              
                $s2 = [text.encoding]::utf8.getbytes($tr).Length.ToString('d6') + ':' + $tr                     
                $s2 = [text.encoding]::utf8.getbytes($s2)
              
                Write-Log "Sending symbols to remote: '$tr'"

                $remoteserver.Write($s2, 0, $s2.Length)
                $resultMessage = get_message($remoteserver)
                Write-Log "Remote result: '$resultMessage'"
            }

            Write-Log "Connecting to $($ps_computer):$ps_port"
            
            $ps_client = New-Object System.Net.Sockets.TcpClient -ArgumentList ($ps_computer, $ps_port)
            $remoteserver = $ps_client.GetStream()
            $remoteserver.ReadTimeout = $REMOTE_SERVER_READ_TIMEOUT

            $slimBufferString = [Text.Encoding]::UTF8.GetString($originalslimbuffer, 0, $originalslimbuffer.Length)
            Write-Log "Sending table to remote: '$slimBufferString'"

            $remoteserver.Write($originalslimbuffer, 0, $originalslimbuffer.Length)           
            
            $resultMessage = get_message($remoteserver)
            Write-Log "Remote result: '$resultMessage'"

            $result[$ps_computer] = $resultMessage
    
            #backward symbols sharing
            foreach($symbol in Get-RemoteSlimSymbols($slimBufferString))
            {
                $__pattern__ = "$($symbol.id):\d{6}:(?<value>.+?):\]"
                $slimsymbols[$symbol.name] = $result[$ps_computer] | Select-String $__pattern__ | % {
                    $_.matches
                } | % {
                    $_.Groups[1].Value
                }
            }
      
            $remoteserver.Close()         
            $ps_client.Close()
        }

        $res = $ps_buf1 + $ps_buf2
        $ps_fitnesse.Write($res, 0, $res.Length)
    }
    catch [System.Exception] 
    {
        $send = '[000002:' + (slimlen $ps_table[0][0]) + ':' + $ps_table[0][0] + ':' + (slimlen "${slimexception}:$($_.Exception.Message)") + ':' + "${slimexception}:$($_.Exception.Message)" + ':]'
        $send = (slimlen $send) + ':' + $send + ':'
        $send = [text.encoding]::utf8.getbytes((pack_results $send))
        $ps_fitnesse.Write($send, 0, $send.Length)
    }
}


function Get-SlimTable($slimchunk) 
{
    $ps_exp = $slimchunk -replace "'", "''" -replace '000000::', '000000:blank:'  -replace '(?S):\d{6}:(.*?)(?=(:\d{6}:|:\]))', ',''$1''' -replace "'(\[\d{6})'", '$1' -replace ':\d{6}:', ',' -replace ':\]', ')' -replace '\[\d{6},', '(' -replace "'blank'", "''"

    Write-Verbose -Message $ps_exp

    $script:ps_table = Invoke-Expression -Command $ps_exp
}


function Test-OneRowTable($ps_table) 
{
    !($ps_table[0] -is [array])
}

function Get-SlimLength($ps_obj) 
{
    if($ps_obj -is [array])
    {
        $ps_obj.Count.ToString('d6')
    }
    elseif($ps_obj -is 'System.Collections.Generic.KeyValuePair[String,Object]')
    {
        (1).ToString('d6')
    }
    else 
    {
        $ps_obj.ToString().Length.ToString('d6')
    }
}
New-Alias -Name slimlen -Value Get-SlimLength

function ischunk($ps_msg) 
{
    $ps_msg.StartsWith('[') -and $ps_msg.EndsWith(']')
}

function send_slim_version($ps_stream) 
{
    $ps_version = [text.encoding]::ascii.getbytes($slimver)
    $ps_stream.Write($ps_version, 0, $ps_version.Length)
}

$ps_buf1 = $null
$ps_buf2 = $null

function get_message_length($ps_stream) 
{
    $script:ps_buf1 = New-Object -TypeName byte[] -ArgumentList 7

    $t = read_message $ps_stream $ps_buf1
    [int][text.encoding]::utf8.getstring($ps_buf1, 0, 6)

    Write-Verbose -Message "Length: $ps_buf1"
}

function read_message($ps_stream, $buf, $offset = 0)
{
    Write-Verbose -Message 'Reading message....'
    # But if the read operation completed with the zero bytes. This means that client is not going to send anything. Right?
    
    $ps_size = $buf.Count

    while($offset -lt $ps_size)
    {
        $error.clear()
        $offset += $ps_stream.Read($buf, $offset, $ps_size - $offset)

        Write-Verbose -Message "Offset $offset"

        if ($error) 
        {
            Write-Verbose -Message $error.Exception
            break
        }
        if($offset -eq 0)
        {
            Write-Verbose -Message 'Offset should not be zero!'
            break
        }
    }

    Write-Verbose -Message "Got $buf"
}

function get_message($ps_stream)
{
    Write-Verbose -Message 'Getting Message Length ...'

    $ps_size = get_message_length($ps_stream)

    Write-Verbose -Message "Length: $ps_size"

    $script:ps_buf2 = New-Object -TypeName byte[] -ArgumentList $ps_size
    $t = read_message $ps_stream $ps_buf2
    [text.encoding]::utf8.getstring($ps_buf2)
}

function ObjectTo-Slim($ps_obj)
{
    $slimview = '[000002:' + (slimlen $ps_prop) + ':' + $ps_prop+ ':'
    if($($ps_obj.$ps_prop) -eq $null -or $($ps_obj.$ps_prop) -is [system.array])
    {
        $slimview += '000004:null:]'
    }
    else
    {
        $slimview += (slimlen $($ps_obj.$ps_prop)) + ':' + $($ps_obj.$ps_prop).ToString() + ':]'
    }
    (slimlen $slimview) + ':' + $slimview + ':'
}

function ConvertTo-Json20([object] $item)
{
    Add-Type -AssemblyName system.web.extensions
    $ps_js = New-Object -TypeName system.web.script.serialization.javascriptSerializer
    return $ps_js.Serialize($item) 
}

function PropertyTo-Slim($ps_obj,$ps_prop)
{
    $slimview = '[000002:' + (slimlen $ps_prop) + ':' + $ps_prop+ ':'
    if($($ps_obj.$ps_prop) -eq $null)
    {
        $slimview += '000004:null:]'
    }
    elseif($($ps_obj.$ps_prop) -is [system.array] -or $($ps_obj.$ps_prop) -is [psobject])
    {
        if ($Host.Version.Major -ge 3) 
        {
            $slimview += (ConvertTo-Json -Compress -InputObject $($ps_obj.$ps_prop)) |% {
                (slimlen $_) + ':' + $_.ToString() + ':]'
            } 
        }
        else 
        {
            $slimview += ConvertTo-Json20 ($ps_obj.$ps_prop) |% {
                (slimlen $_) + ':' + $_.ToString() + ':]'
            } 
        }        
    }
    else
    {
        $slimview += (slimlen $($ps_obj.$ps_prop)) + ':' + $($ps_obj.$ps_prop).ToString() + ':]'
    }
    (slimlen $slimview) + ':' + $slimview + ':'
}

function Convert-Hashtable-2Object($hashtable)
{
    $ps_object = New-Object -TypeName PSObject
    $hashtable.GetEnumerator() | % {
        Add-Member -InputObject $ps_object -MemberType NoteProperty -Name $_.Name -Value $_.Value 
    }
    Add-Member -InputObject $ps_object -MemberType NoteProperty -Name 'SLIM_COMPUTERNAME' -Value $env:COMPUTERNAME
    $ps_object
}

function Convert-KeyValuePair-2Object($kvp)
{
    $ps_obj = New-Object -TypeName PSObject -Property @{
        Key               = $kvp.Key
        Value             = $kvp.Value.ToString()
        SLIM_COMPUTERNAME = $env:COMPUTERNAME
    }
    $ps_obj
}

function ConvertTo($ps_str) 
{
    $ps_object = New-Object -TypeName PSObject

    Add-Member -InputObject $ps_object -MemberType NoteProperty -Name 'Value' -Value $ps_str
    Add-Member -InputObject $ps_object -MemberType NoteProperty -Name 'SLIM_COMPUTERNAME' -Value $env:COMPUTERNAME

    $ps_object
}

function ConvertTo-SimpleObject($ps_obj)
{
    ConvertTo $ps_obj.ToString() 
}
function GetNullObject
{
    ConvertTo 'Null' 
}

function ResultTo-List($list)
{
    if($null -eq $list)
    {
        $slimvoid
    }
    elseif ($list -is [array])
    {
        $result = '[' + (slimlen $list) + ':'
        foreach ($ps_obj in $list)
        {
            if ($ps_obj -is 'system.collections.generic.dictionary[string,object]')
            {
                $ps_obj = [hashtable] $ps_obj
            }
            if($ps_obj -is [hashtable] )
            {
                $ps_obj = Convert-Hashtable-2Object $ps_obj
            }
            if($ps_obj -is [string] -or $ps_obj -is [int])
            {
                $ps_obj = ConvertTo-SimpleObject $ps_obj
            }
            if ($ps_obj -is 'system.collections.generic.keyvaluepair[string,object]')
            {
                $ps_obj = Convert-KeyValuePair-2Object $ps_obj
            }
            if ($null -eq $ps_obj)
            {
                $ps_obj = GetNullObject
            }
            $fieldscount = ($ps_obj  | Get-Member -MemberType Property, NoteProperty  | Measure-Object).Count
            $itemstr = '[' +  $fieldscount.ToString('d6') + ':'
            $ps_obj  | Get-Member -MemberType Property, NoteProperty | % {
                $itemstr += PropertyTo-Slim $ps_obj $_.Name 
            }
            $itemstr += ']'
    
            $result += (slimlen $itemstr) + ':' + $itemstr + ':'
        } 
        $result += ']'
        $result
    }
    else
    {
        $list
    }
}

function ResultTo-String($res)
{
    if($res -eq $null)
    {
        $slimvoid
    }
    else
    {
        $result = ''
        foreach ($ps_obj in $res)
        {
            $result += $ps_obj.ToString()
            $result += ','
        }
        $result.TrimEnd(',')
    }
}

function Exec-Script( $Script ) 
{
    # Clear out any prior errors. After executing the test, if error[0] <> $null, we know it came from the test.
    $Error.Clear()   
    try 
    {
        if ( $script:SLIM_ABORT_TEST ) 
        {
            # If another critical error has already been detected, we immediately end this 
            # test w/o executing it and return an error.
            $result = "${slimexception}:ABORT_SLIM_TEST:message:<<ABORT_TEST_INDICATED:Test not run>>"
        }
        elseif ( $script:SLIM_ABORT_SUITE ) 
        {
            # If another critical error has already been detected, we immediately end this 
            # test w/o executing it and return an error.
            $result = "${slimexception}:ABORT_SLIM_TEST:message:<<ABORT_SUITE_INDICATED:Test not run>>"
        }
        else 
        {
            # execute the test and store the result.
            $result = Invoke-Expression -Command $Script
            # preserve the $matches value, if set by the expression
            $script:matches = $matches
        }
    }
    catch [System.Exception] 
    {
        switch($_.Exception.GetType().FullName) {
            'System.Management.Automation.CommandNotFoundException' 
            {
                $exc_type = "${slimexception}:COMMAND_NOT_FOUND:"
                $exc_msg  = $exc_type + $_
            }
            'System.Management.Automation.ActionPreferenceStopException' 
            {
                # if $ErrorActionPreference is set to stop and an error occurred, we end up here
                $script:SLIM_ABORT_TEST = $true
                $exc_type = "${slimexception}:ABORT_SLIM_TEST:"
                $exc_msg  = $exc_type + $_ 
            }
            'System.Management.Automation.RuntimeException' 
            {
                $e = $_
                switch -regex ( $Error[0].FullyQualifiedErrorId ) {
                    # If the user script has thrown an exception and it starts with "StopTest", no further 
                    # tests should execute.
                    '^Stop(Test|Suite):?(.*)?' 
                    {
                        if ( $matches[2] ) 
                        {
                            # The exception provides additional details about the error.
                            $exc_type = "${slimexception}:ABORT_SLIM_TEST:"
                            $exc_msg  = $exc_type + $matches[1] + ' aborted. Additional Info[' + $matches[2] + ']'
                        }
                        else 
                        {
                            # No other details provided... just a throw "StopTest" was executed
                            $exc_type = "${slimexception}:ABORT_SLIM_TEST:"
                            $exc_msg  = $exc_type + $matches[1] + ' aborted.' 
                        }
                        $script:SLIM_ABORT_TEST = $true # Make sure any additional tests in the table abort.
                        if ( $matches[1] -eq 'Suite' ) 
                        {
                            $script:SLIM_ABORT_SUITE = $true # Make sure any additional tests in the table abort.
                        }
                    }
                    default 
                    { 
                        $exc_type = $slimexception + ':' + $_ + ':'
                        $exc_msg  = $exc_type + ((Format-List -InputObject $error[0].Exception | Out-String) -replace "`r`n", '' )
                    }
                }
            }
            default 
            {
                $exc_type = "${slimexception}:$($error[0].Exception):"
                $exc_msg  = $exc_type + ((Format-List -InputObject $error[0].Message | Out-String) -replace "`r`n", '' )
            }
        }
    }
    finally 
    {
        if ( $Error[0] -ne $null ) 
        {
            # An error has occurred. If $exc_type has a value, it was caught above.
            if ( $exc_type -gt '' ) 
            {
                #an error occurred, so check $ErrorActionPreference to see if it's set to Stop
                if ( $global:ErrorActionPreference -eq 'Stop' ) 
                {
                    # if the user indicated they want to stop on all errors, Stop.
                    $exc_type = "${slimexception}:ABORT_SLIM_TEST:"
                }
                if ( $exc_type -eq "${slimexception}:ABORT_SLIM_TEST:" ) 
                {
                    $script:SLIM_ABORT_TEST = $true
                }
                $result = $exc_type+'message:<<'+$exc_msg+'>>'
            }
            else 
            {
                # This is a non-terminating error and not caught as part of the special types
                # above, so simply return the error text as the result of the instruction
                $result = (''+$Error[0])
            }
        }
    }
    return $result
}


function Invoke-SlimCall($fnc)
{
    switch ($fnc){
        'query' 
        {
            $result = Exec-Script -Script $Script__ 
        }
        'eval'  
        {
            $result = Exec-Script -Script $Script__ 
        }
        default 
        { 
            if ((Table-Type) -eq 'ScriptTableActor') 
            {
                $result = "${slimexception}:COMMAND_NOT_FOUND " + $_
            }
            else
            {
                $result = $slimvoid 
            }
        }
    }
    $result
}

function Set-Script($s, $fmt)
{
    if(!$s)
    {
        return 
    }

    $s = $s -replace '<table class="hash_table">\r\n', '@{' -replace '</table>', '}' -replace '\t*<tr class="hash_row">\r\n', '' -replace '\t*</tr>\r\n', '' -replace '\t*<td class="hash_key">(.*)</td>\r\n', '''$1''=' -replace '\t*<td class="hash_value">(.*)</td>\r\n', '''$1'';'
    if($s.TrimStart().StartsWith('<pre>'))
    {
        $s = $s -replace '</?pre>' #workaround fitnesse strange behavior
    }

    if($slimsymbols.Count)
    {
        $slimsymbols.Keys | ? {
            !($s -cmatch "\`$$_\s*=")
        } | ? {
            $slimsymbols[$_] -is [string] 
        } | % {
            $s = $s -creplace "\`$$_\b", $slimsymbols[$_] 
        }
    }

    if($slimsymbols.Count)
    {
        $slimsymbols.Keys | % {
            Set-Variable -Name $_ -Value $slimsymbols[$_] -Scope Global
        }
    }

    $s = [string]::Format( $fmt, $s)
    if($s.StartsWith('function', $true, $null))
    {
        Set-Variable -Name Script__ -Value ($s -replace 'function\s+(.+)(?=\()', 'function script:$1') -Scope Global
    }
    else
    {
        Set-Variable -Name Script__ -Value ($s -replace '\$(\w+)((?=\s*[\+|\*|\-|/|%]*=)|(?=\s*,\s*\$\w+.*=))', '$script:$1') -Scope Global
    }
}

function make($ins)
{
    if('ESXI'.Equals($ins[3],[System.StringComparison]::OrdinalIgnoreCase))
    {
        $script:QueryFormat__ = Get-QueryFormat $ins
        $script:EvalFormat__ = Get-EvalFormat $ins
    }
    'OK'
}

function Id() 
{
    $script:ps_row[0]
}
function Operation() 
{
    $script:ps_row[1]
}
function Module() 
{
    $script:ps_row[2]
}
function Table-Type() 
{
    $script:ps_row[2]
}

function Invoke-SlimInstruction()
{
    # Some slim instruction samples:
    # scriptTable_0_0 call scriptTableActor eval $server.Kill()
    # scriptTable_0_0 callAndAssign CurrentPID scriptTableActor eval $PID
    # decisionTable_3_6 call decisionTable_3 setHomePhone 800-555-1212
    # decisionTable_3_0 make decisionTable_3 new-object PSObject -Property @{ Name = "$First $Last"; }
    $ins = $script:ps_row

    (Id)

    switch -wildcard (Operation) {

        'import' 
        {
            Invoke-Expression -Command ". .\$(Module)" 
            'OK'
            return
        }

        'make' 
        {
            make $ins
            Set-Script $ins[$ins.Count - 1] $QueryFormat__
            return
        }

        'callAndAssign' 
        {
            $symbol = $ins[2]
            $ins = $ins[0, 1 + 3 .. $ins.Count]
        }

        'call*' 
        { 
            if($ins[2] -match '^decisionTable|^dynamicDecisionTable')
            {
                if($ins[3] -match 'table|beginTable|reset|endTable')
                {
                    '/__VOID__/'
                    return
                }
                elseif($ins[3][0..2] -join '' -eq 'set')
                {
                    # Processing decision table inputs, i.e. 'setSomeParameter'
                    $ps_input_name = $($ins[3].Substring(3))                    
                    $ps_input_value = "'$($ins[4])'"

                    # Check if it is dynamic decision table
                    if(-not $ps_input_name)
                    {
                        $ps_input_name = $ins[4]
                        $ps_input_value = "'$($ins[5])'"
                    }

                    Write-Log "Set variable: `$$ps_input_name = $ps_input_value"
                    Invoke-Expression "`$script:$ps_input_name = $ps_input_value"

                    '/__VOID__/'
                    return
                }
                elseif($ins[3] -eq 'execute')
                {
                    Write-Log "Executing decision table row: '$Script__'"

                    # Store the decision table test time.
                    $script:decision_time = Measure-Command {
                        $script:decision_result = Exec-Script -Script "$Script__ 2>&1"
                    }
                    
                    Write-Log "Result: '$script:decision_result', execution time: $($script:decision_time.ToString())"

                    $slimvoid
                    #$script:decision_result
                    return
                }
                else
                {
                    switch -regex ($ins[3]) {
                        # Support requesting the amount of time it took to process a decision table row.
                        '^Time(?<comp>\w+)?'     
                        {
                            if ( $Matches.ContainsKey( 'comp') ) 
                            {
                                switch ( $matches.comp ) {
                                    'Seconds'      
                                    {
                                        $script:decision_time.TotalSeconds 
                                    }
                                    'Days'         
                                    {
                                        $script:decision_time.TotalDays 
                                    }
                                    'Hours'        
                                    {
                                        $script:decision_time.TotalHours 
                                    }
                                    'Minutes'      
                                    {
                                        $script:decision_time.TotalMinutes 
                                    }
                                    'Milliseconds' 
                                    {
                                        $script:decision_time.TotalMilliseconds 
                                    }
                                    default        
                                    {
                                        'Invalid Duration: $_' 
                                    }
                                }
                            }
                            else 
                            {
                                $script:decision_time.TotalSeconds
                            }
                            break
                        }
                        '^Result$'   
                        {
                            ResultTo-String ($script:decision_result)
                            if ($symbol) 
                            {
                                $slimsymbols[$symbol] = $script:decision_result
                            }
                            break
                        }
                        '^Result(\S+)$'   
                        {
                            $prop = $Matches[1]
                            $prop = $prop -replace '_', '.'
                            ResultTo-String (Invoke-Expression ('$script:decision_result.'+$prop))
                            if ($symbol) 
                            {
                                $slimsymbols[$symbol] = Invoke-Expression ('$script:decision_result.'+$prop)
                            }
                            break
                        }
                        '^(\S+)$'    
                        {
                            $prop = $Matches[1]
                            $prop = $prop -replace '_', '.'
                            ResultTo-String (Invoke-Expression ('$script:decision_result.'+$prop))
                            if ($symbol) 
                            {
                                $slimsymbols[$symbol] = Invoke-Expression ('$script:decision_result.'+$prop)
                            }
                        }
                        default    
                        {
                            'Not Implemented'       
                        }
                    }
                    return
                }
            }
        }
    }
  
    if($ins[3] -ne 'query' -and $ins[3] -ne 'table')
    {
        Set-Script $ins[4] $EvalFormat__
    }
 
    Write-Log "Executing command: '$Script__'"

    # Measure the amount of time this step or command takes
    $script:Command_Time = Measure-Command  {
        # Execution of the test's code occurs here. During the 'make' step this is simple
        # the execution of the 'make' procedure.
        $result = Invoke-SlimCall $ins[3]
    }

    Write-Log "Result: '$result', execution time: $($script:Command_Time.ToString())"

    if($symbol)
    {
        $slimsymbols[$symbol] = $result
    }
  
    $error.clear()
    switch ($ins[3]){
        'query' 
        {
            if(($null -eq $result) -or ($result -is 'System.Collections.Generic.Dictionary[String,Object]' -and  $result.Count -eq 0))
            {
                $result = ResultTo-List @()
            }
            else
            {
                $result = ResultTo-List @($result)
            }
        }
        'eval'  
        {
            $result = ResultTo-String $result 
        }
    }
    if ($result -is [String]) 
    {
        $result.TrimEnd("`r`n")
    }
    else 
    {
        $result
    }
}

function Process-Instruction($ins)
{
    $script:ps_row = $ins
    $result = Invoke-SlimInstruction

    $s = '[000002:' + (slimlen $result[0]) + ':' + $result[0] + ':' + (slimlen $result[1]) + ':' + $result[1] + ':]'
    (slimlen $s) + ':' + $s + ':'
}

function pack_results($results)
{
    if($results -is [array])
    {
        $ps_send = '[' + (slimlen $results) + ':'
        $results | % {
            $ps_send += $_
        }
    }
    else
    {
        $ps_send = "[000001:$results"
    }
    $ps_send += ']'
    [text.encoding]::utf8.getbytes($ps_send).Length.ToString('d6') + ':' + $ps_send
}


function check_remote($ps_table) 
{
    if( !(Test-OneRowTable $ps_table) ) 
    {
        $ps_table = $ps_table[0]
    }

    if($ps_table[0].StartsWith('scriptTable_') -or $ps_table[0].StartsWith('queryTable_'))
    {
        if('Remote' -eq $ps_table[3])
        {
            set_remote_targets($ps_table[4])
        }
        else
        {
            $script:Remote = $false
        }
    }
}

function set_remote_targets($ps_cell) 
{
    $script:Remote = $true
    $script:targets = $null
  
    # The CommandNotFoundException is expected here if target is not an expression,
    # for example if it is just 'remote_host'.
    try {
        $script:targets = Invoke-Expression -Command $ps_cell
    } catch [System.Management.Automation.CommandNotFoundException] {}

    if($script:targets -eq $null)
    {
        $script:targets = $ps_cell.Split(',') | %{ $_.Trim(', ') }
    }
}

function process_table() 
{
    if(Test-OneRowTable $script:ps_table)
    {
        $ps_results = Process-Instruction $script:ps_table 
    }
    else 
    {
        $ps_results = $script:ps_table | % {
            Process-Instruction $_ 
        } 
    }

    $ps_results
}

function process_message($ps_stream)
{
    if(!$ps_stream.CanRead )
    {
        return 'bye' 
    }

    Write-Verbose -Message 'Started processing message.'

    $script:SLIM_ABORT_TEST = $false
    $error.clear()
    $ps_msg = get_message($ps_stream)

    $ps_msg

    if ($error) 
    {
        return 'bye' 
    }

    if( !(ischunk $ps_msg) )
    {
        return 
    }

    $script:QueryFormat__ = $script:EvalFormat__ = '{0}'
    Get-SlimTable $ps_msg

    check_remote($script:ps_table)

    if($Remote -eq $true)
    {
        Write-Verbose -Message "Buffer1 $ps_buf1"
        Write-Verbose -Message "Buffer2 $ps_buf2"

        Write-Log 'Processing table remotely'
        process_table_remotely $script:ps_table $ps_stream;

        Write-Log 'Remote processing completed'

        return
    }
  
    $ps_results = process_table

    $ps_send = [text.encoding]::utf8.getbytes((pack_results $ps_results))
    $ps_stream.Write($ps_send, 0, $ps_send.Length)
}

function process_message_ignore_remote($ps_stream)
{
    Write-Verbose -Message 'Process Message & Ignore Remote'

    $ps_msg = get_message($ps_stream)

    if(ischunk($ps_msg))
    {
        $script:QueryFormat__ = $script:EvalFormat__ = '{0}'
        $ps_table = Get-SlimTable $ps_msg

        $ps_results = process_table

        $ps_send = [text.encoding]::utf8.getbytes((pack_results $ps_results))
        $ps_stream.Write($ps_send, 0, $ps_send.Length)
    }
}

function Run-SlimServer($ps_server) 
{
    Write-Log 'Starting local PowerSlim server...'

    $ps_fitnesse_client = $ps_server.AcceptTcpClient()
    $ps_fitnesse_stream = $ps_fitnesse_client.GetStream()
    $ps_fitnesse_stream.ReadTimeout = $REQUEST_READ_TIMEOUT
 
    send_slim_version($ps_fitnesse_stream)
    $ps_fitnesse_client.Client.Poll(-1, [System.Net.Sockets.SelectMode]::SelectRead) | Out-Null

    while('bye' -ne (process_message($ps_fitnesse_stream))) { }
    $ps_fitnesse_client.Close()
}

function Run-RemoteServer($ps_server)
{
    Write-Log 'Waiting for request...'
    while($ps_fitnesse_client = $ps_server.AcceptTcpClient())
    {
        Write-Log 'Request accepted'
        $ps_fitnesse_stream = $ps_fitnesse_client.GetStream()
        $ps_fitnesse_stream.ReadTimeout = $REQUEST_READ_TIMEOUT
    
        process_message_ignore_remote($ps_fitnesse_stream)
        $ps_fitnesse_stream.Close()
        $ps_fitnesse_client.Close()
        Write-Log 'Waiting for request...'
    }
}

if (!$args.Length) 
{ 
    Write-Output 'No arguments provided!'
    Write-Output 'Sample: .\slim.ps1 <port, i.e. 35> [Server]'
    return; 
}

$ps_port = $args[0]
$ps_server = New-Object -TypeName System.Net.Sockets.TcpListener -ArgumentList ($ps_port)
$ps_server.Start()

if($args[1] -eq 'Server') 
{
    Run-RemoteServer $ps_server 
}
else 
{
    Run-SlimServer $ps_server
}

$ps_server.Stop()
