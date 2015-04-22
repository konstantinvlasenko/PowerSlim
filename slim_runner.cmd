@echo off

rem This file used in the 'SuiteLogging' suite.
rem It redirects stdout to the file specified in first argument (%1).
rem We cannot start slim from FitNesse this way without such file because FitNesse always adds slim port to the end of command line.

del %1 2> nul
PowerShell -NonInteractive -ExecutionPolicy unrestricted -file .\slim.ps1 %2 > %1
del %1