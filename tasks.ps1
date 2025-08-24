#Requires -Module InvokeBuild

task Lint LintPowerShell, LintDocker, LintYaml

task LintPowerShell {
    Invoke-ScriptAnalyzer -Path docker/compositions/core -Recurse
}

task LintDocker {
    Get-ChildItem -Path . -Name "Dockerfile" -Recurse | ForEach-Object {
        docker run --rm -i hadolint/hadolint < $_
    }
}

task Deploy Lint, {
    & "docker/compositions/core/deploy.ps1" -Verbose
}

task Test {
    & "docker/compositions/core/test-scripts.ps1"
}
