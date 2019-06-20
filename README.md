PowerSlim - An implementation of FitNesse Slim in PowerShell

https://powerslim.slack.com

```
!define TEST_SYSTEM {slim}
!define SLIM_PORT (8090)
!define COMMAND_PATTERN (powershell -NonInteractive -file ./slim.ps1)
```
Examples are available in the acceptance tests [FitnesseRoot/PowerSlim](https://github.com/konstantinvlasenko/PowerSlim/tree/master/FitNesseRoot/PowerSlim) and in the examples FitnesseRoot/ExampleS

### Supported Platforms
 * Windows
 * Linux
 * Ubuntu

### March 4, 2017

  * Now you can run PowerSlim on Linux or Ubuntu server! Thanks to [@mikeplavsky](https://github.com/mikeplavsky)

### March 1, 2017

 * [Fitnesse 20161106](http://fitnesse.org/.FrontPage.FitNesseDevelopment.FitNesseRelease20161106) introduced a breaking change. _FitNesse and Slim can now communicate over stdin/stdout. This removes the hassle with network ports [977](https://github.com/unclebob/fitnesse/pull/977)_
 You need to set [SLIM_PORT](https://github.com/konstantinvlasenko/PowerSlim/blob/02dc82325d639123874beebbeb5229ba202f867b/FitNesseRoot/PowerSlim/OriginalMode/content.txt#L2) variable to make PowerSlim work again
   

### October 7, 2016

 * [Expect Error](https://github.com/konstantinvlasenko/PowerSlim/blob/master/FitNesseRoot/PowerSlim/OriginalMode/SuiteCommon/TestExpectError/content.txt)

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
