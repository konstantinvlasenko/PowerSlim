PowerSlim - An implementation of FitNesse Slim in PowerShell

https://powerslim.slack.com

```
!define TEST_SYSTEM {slim}
!define SLIM_PORT (8090)
!define COMMAND_PATTERN (pwsh -NoProfile -NonInteractive -File ./slim.ps1)
```
Requires PowerShell 7+ (`pwsh`) on any platform, or Windows PowerShell 5.1 (use `powershell` instead of `pwsh` in `COMMAND_PATTERN`). PowerShell 2.0–5.0 are no longer supported.

### Running the acceptance tests
```
curl -L -o fitnesse-standalone.jar https://repo1.maven.org/maven2/org/fitnesse/fitnesse/20260313/fitnesse-20260313-standalone.jar
java -jar fitnesse-standalone.jar -o -p 8085 -c "PowerSlim.OriginalMode?suite&format=text"
java -jar fitnesse-standalone.jar -o -p 8085 -c "PowerSlim.SuiteREST?suite&format=text"
```
`PowerSlim.SuiteWrongFailedException` fails on purpose; it is checked from `SuiteCommon.TestScenario`.

### Remote agents
`./slim.ps1 <port> server` starts a remote agent. It listens on `127.0.0.1` by default.
An agent runs any PowerShell it receives, unauthenticated, so only expose it on a trusted private network: `./slim.ps1 35 server -BindAddress 0.0.0.0`.
Targets without an explicit port (`|script|Remote|myhost|`) use port 35, or `$env:POWERSLIM_REMOTE_PORT` if set.

Examples are available in the acceptance tests [FitnesseRoot/PowerSlim](https://github.com/konstantinvlasenko/PowerSlim/tree/master/FitNesseRoot/PowerSlim) and in the examples FitnesseRoot/ExampleS

### Supported Platforms
 * Windows: PowerShell 7+ or Windows PowerShell 5.1
 * Linux and macOS: PowerShell 7+

### March 4, 2017

  * Now you can run PowerSlim on Linux or Ubuntu server! Thanks to [@mikeplavsky](https://github.com/mikeplavsky)

### March 1, 2017

 * [Fitnesse 20161106](http://fitnesse.org/.FrontPage.FitNesseDevelopment.FitNesseRelease20161106) introduced bracking change. _FitNesse and Slim can now communicate over stdin/stdout. This removes the hassle with network ports [977](https://github.com/unclebob/fitnesse/pull/977)_
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
