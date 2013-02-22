#
# "THE BEER-WARE LICENSE" (Revision 42):
# <konstantin.vlasenko@gmail.com> wrote this file. As long as you retain this notice
# you can do whatever you want with this stuff. If we meet some day, and you
# think this stuff is worth it, you can buy me a beer in return.
#
function script:Refresh-EnvironmentVariable($name){
	[Environment]::SetEnvironmentVariable($name, [Environment]::GetEnvironmentVariable($name,"Machine"), "Process")
}