PowerSlim - An implementation of FitNesse Slim in PowerShell

All stuff is under the [Beer-Ware-License](http://en.wikipedia.org/wiki/Beerware).

!define TEST_SYSTEM {slim}
!define COMMAND_PATTERN (PowerShell -NonInteractive -ExecutionPolicy unrestricted -file .\slim.ps1)

Examples are available in the acceptance tests FitnesseRoot/PowerSlim and in the examples FitnesseRoot/ExampleS

Requirements:
The Windows PowerShell 3.0 should be installed.
The PowerShell 3.0 comes integrated with Windows 8 and with Windows Server 2012. Operating systems also supported are Windows 7 Service Pack 1, Windows Server 2008 R2 SP1, Windows Server 2008 Service Pack 2.

Please Note: You can still use the PowerShell 2.0 or work in backward compatibility with the PowerShell 2.0. But in order to support arrays and PSObjects verification in Queries the ConvertTo-Json CMDLet is used introduced in the PowerShell 3.0. For the verification to work with the PowerShell 2.0 you have to implement ConvertTo-Json CMDLet functionality via e.g. System.Web.Script.Serialization.JavaScriptSerializer (upgarade to .NET Framework 3.5 is reqquired). Otherwise you can stub the ConvertTo-Json CMDLet.

### December 19, 2012

* [Target as expression](https://github.com/konstantinvlasenko/PowerSlim/blob/master/FitNesseRoot/PowerSlim/SuiteRemoting/TestTargetAsExpression/content.txt)

### November 14, 2012

* [Decision table magic](https://github.com/konstantinvlasenko/PowerSlim/blob/master/FitNesseRoot/PowerSlim/TestDecisionTable/content.txt)


