function script:Refresh-EnvironmentVariable($name){
	[Environment]::SetEnvironmentVariable($name, [Environment]::GetEnvironmentVariable($name,"Machine"), "Process")
}