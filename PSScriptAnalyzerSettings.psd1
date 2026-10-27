# PSScriptAnalyzer settings used by CI: Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
@{
  Severity     = @('Error', 'Warning')
  ExcludeRules = @(
    # PowerSlim evaluates test-table cells as PowerShell by design
    'PSAvoidUsingInvokeExpression',
    # Console output is intended in the runner log and the test scripts
    'PSAvoidUsingWriteHost',
    # Renaming the existing functions (verbs, plural nouns, Write-Log) is left for the slim.ps1 refactor
    'PSUseApprovedVerbs',
    'PSUseSingularNouns',
    'PSAvoidOverwritingBuiltInCmdlets',
    # Internal helpers, not user-facing cmdlets
    'PSUseShouldProcessForStateChangingFunctions'
  )
}
