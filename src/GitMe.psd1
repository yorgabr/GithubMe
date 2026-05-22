@{
    RootModule           = 'GitMe.psm1'
    ModuleVersion        = '1.0.0'
    CompatiblePSEditions = @('Desktop', 'Core')
    GUID                 = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
    Author               = 'Yorga Babuscan'
    CompanyName          = 'Yorga Babuscan'
    Copyright            = '(c) 2026 Yorga Babuscan. Licensed under GPL-3.0.'
    Description          = 'Professional Git repository initializer with remote publishing support for GitHub, GitLab, and local/CIFS remotes. Idempotent, tab-completed, and CI/CD ready.'
    PowerShellVersion    = '5.1'
    RequiredModules      = @()
    FunctionsToExport    = @('Invoke-Gitme', 'Get-GitmeTabCompletion')
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @('gitme')
    PrivateData          = @{
        PSData = @{
            Tags                     = @('Git', 'GitHub', 'GitLab', 'Repository', 'Automation', 'DevOps', 'SemVer', 'ConventionalCommits')
            LicenseUri               = 'https://github.com/yorgabr/GitMe/blob/main/docs/LICENSE.md'
            ProjectUri               = 'https://github.com/yorgabr/GitMe'
            ReleaseNotes             = 'https://github.com/yorgabr/GitMe/releases'
            RequireLicenseAcceptance = $false
        }
    }
    HelpInfoURI          = 'https://github.com/yorgabr/GitMe#readme'
}