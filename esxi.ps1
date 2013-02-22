#
# "THE BEER-WARE LICENSE" (Revision 42):
# <konstantin.vlasenko@gmail.com> wrote this file. As long as you retain this notice
# you can do whatever you want with this stuff. If we meet some day, and you
# think this stuff is worth it, you can buy me a beer in return.
#
function script:Set-PowerSlimRemoting{
	Set-Variable -Name PowerSlimRemoting__ -Value "VMware.VimAutomation.Core" -Scope Global
	Add-PSSnapin $PowerSlimRemoting__
	Set-Variable -Name Host__ -Value $args[1] -Scope Global
	Set-Variable -Name HostUser__ -Value $args[2] -Scope Global
	Set-Variable -Name HostPswd__ -Value $args[3] -Scope Global
	Connect-VIServer -Server $Host__ -User $HostUser__ -Password $HostPswd__
}

function script:Get-QueryFormat($ins){
	$vm = $ins[4].Trim(',')
	"Invoke-VMScript '{0} | ConvertTo-CSV -NoTypeInformation' (Get-VM $vm) -HostUser $HostUser__ -HostPassword '$HostPswd__' -ToolsWaitSecs 60 -GuestUser $($ins[5]) -GuestPassword '$($ins[6])' | ConvertFrom-CSV"
}

function script:Get-EvalFormat($ins){
	$vm = $ins[4].Trim(',')
	"Invoke-VMScript '{0}' (Get-VM $vm) -HostUser $HostUser__ -HostPassword '$HostPswd__' -ToolsWaitSecs 60 -GuestUser $($ins[5]) -GuestPassword '$($ins[6])'"
}
