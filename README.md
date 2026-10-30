PowerSlim - An implementation of FitNesse Slim in PowerShell

[![CI](https://github.com/konstantinvlasenko/PowerSlim/actions/workflows/ci.yml/badge.svg)](https://github.com/konstantinvlasenko/PowerSlim/actions/workflows/ci.yml)

https://powerslim.slack.com

```
!define TEST_SYSTEM {slim}
!define COMMAND_PATTERN (pwsh -NoProfile -NonInteractive -File ./slim.ps1)
```
Requires PowerShell 7+ (`pwsh`) on any platform, or Windows PowerShell 5.1 (use `powershell` instead of `pwsh` in `COMMAND_PATTERN`). PowerShell 2.0–5.0 are no longer supported.

PowerSlim implements [SLIM protocol](https://fitnesse.org/FitNesse/UserGuide/WritingAcceptanceTests/SliM/SlimProtocol.html) version 0.5. FitNesse talks to it over stdin/stdout by default, so no port is needed. Defining `SLIM_PORT` (e.g. `!define SLIM_PORT (8090)`) switches to a TCP port on `127.0.0.1`, as before.

### Symbols
A symbol (`|$name=|eval|...|`) is also a PowerShell variable, so `$name` in code gets its value with its type, and the value is never pasted into the code. FitNesse's text rules still apply where PowerShell would not expand a variable: inside single-quoted strings (`'$name'`), for a name followed by more letters (`"$name_suffix"`) and in command names (`te$name`).

### Aborting and ignoring
`throw 'StopTest'` stops the page and `throw 'StopSuite'` the suite. `throw 'IgnoreScriptTest'` ignores the rest of the script table and `throw 'IgnoreAllTests'` the rest of the page.

### Running the tests
Requires Java 11+ and [Pester](https://pester.dev) 5+.
```
./tests/Invoke-AcceptanceTests.ps1                     # FitNesse suites (downloads the pinned FitNesse jar)
./tests/Invoke-AcceptanceTests.ps1 -Shell powershell   # same, with Windows PowerShell 5.1 running slim.ps1
Invoke-Pester ./tests                                  # unit tests for slim.ps1 and client.ps1
Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
```
CI runs all of these on Linux, macOS and Windows (PowerShell 7 and 5.1).
`PowerSlim.SuiteWrongFailedException` fails on purpose; it is checked from `SuiteCommon.TestScenario`.

### Remote agents
`./slim.ps1 <port> server` starts a remote agent. It listens on `127.0.0.1` by default.
An agent runs any PowerShell it receives, unauthenticated, so only expose it on a trusted private network: `./slim.ps1 35 server -BindAddress 0.0.0.0`.
Targets without an explicit port (`|script|Remote|myhost|`) use port 35, or `$env:POWERSLIM_REMOTE_PORT` if set.

Examples are available in the acceptance tests [FitNesseRoot/PowerSlim](https://github.com/konstantinvlasenko/PowerSlim/tree/master/FitNesseRoot/PowerSlim).

### Supported Platforms
 * Windows: PowerShell 7+ or Windows PowerShell 5.1
 * Linux and macOS: PowerShell 7+

### March 4, 2017

  * Now you can run PowerSlim on Linux or Ubuntu server! Thanks to [@mikeplavsky](https://github.com/mikeplavsky)

### March 1, 2017

 * [Fitnesse 20161106](http://fitnesse.org/.FrontPage.FitNesseDevelopment.FitNesseRelease20161106) introduced bracking change. _FitNesse and Slim can now communicate over stdin/stdout. This removes the hassle with network ports [977](https://github.com/unclebob/fitnesse/pull/977)_
 PowerSlim now supports stdin/stdout, so `SLIM_PORT` is no longer needed.
   

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
