PowerSlim - An implementation of FitNesse Slim in PowerShell

All stuff is under the [Beer-Ware-License](http://en.wikipedia.org/wiki/Beerware).

!define TEST_SYSTEM {slim}

!define COMMAND_PATTERN (PowerShell -NonInteractive -ExecutionPolicy unrestricted -file .\slim.ps1)

Examples are available in the acceptance tests FitnesseRoot/PowerSlim and in the examples FitnesseRoot/ExampleS

Requirements:
Windows PowerShell 3.0 or higher.

Please Note: You can still use the PowerShell 2.0 or work in backward compatibility with the PowerShell 2.0. But in order to support arrays and PSObjects verification in Queries the ConvertTo-Json CMDLet is used introduced in the PowerShell 3.0. For the verification to work with the PowerShell 2.0 you have to implement ConvertTo-Json CMDLet functionality via e.g. System.Web.Script.Serialization.JavaScriptSerializer (upgarade to .NET Framework 3.5 is reqquired). Otherwise you can stub the ConvertTo-Json CMDLet.

### June 17, 2015

 * [REST](https://github.com/konstantinvlasenko/PowerSlim/tree/master/FitNesseRoot/PowerSlim/SuiteREST). New actions: get, post, patch and update.

### May 1, 2015

* [Improved Error Handling](https://github.com/konstantinvlasenko/PowerSlim/pull/71)

### August 25, 2014

* [Improved Error Handling](https://github.com/konstantinvlasenko/PowerSlim/pull/52)

### February 26, 2013

* [Support for Fitnesse Hash Table](https://github.com/konstantinvlasenko/PowerSlim/blob/master/FitNesseRoot/PowerSlim/OriginalMode/SuiteCommon/TestFitnesseHashTable/content.txt)

### December 19, 2012

* [Target as expression](https://github.com/konstantinvlasenko/PowerSlim/blob/master/FitNesseRoot/PowerSlim/SuiteRemoting/TestTargetAsExpression/content.txt)

### November 14, 2012

* [Decision table magic](https://github.com/konstantinvlasenko/PowerSlim/blob/master/FitNesseRoot/PowerSlim/TestDecisionTable/content.txt)
