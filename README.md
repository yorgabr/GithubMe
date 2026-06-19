# GitMe

[![CI/CD](https://github.com/yorgabr/GitMe/actions/workflows/ci.yml/badge.svg)](https://github.com/yorgabr/GitMe/actions/workflows/ci.yml)
[![Coverage](https://codecov.io/gh/yorgabr/GitMe/branch/main/graph/badge.svg)](https://codecov.io/gh/yorgabr/GitMe)
[![PSGallery](https://img.shields.io/powershellgallery/v/GitMe.svg)](https://www.powershellgallery.com/packages/GitMe)
[![License](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](https://github.com/yorgabr/GitMe/blob/main/docs/LICENSE.md)
[![SemVer](https://img.shields.io/badge/SemVer-2.0.0-blue.svg)](https://semver.org)
[![Conventional Commits](https://img.shields.io/badge/Conventional%20Commits-1.0.0-yellow.svg)](https://conventionalcommits.org)

GitMe is a professional-grade PowerShell utility that turns the tedious ritual of starting a new project into a single, predictable command. Whether you are spinning up a repository on GitHub, publishing to a self-hosted GitLab instance, or keeping everything inside your own network on a CIFS share, GitMe handles the boilerplate so you can focus on writing code.

The tool was born from a simple observation: every developer repeats the same steps when creating a repository. Initialise Git, set the developer identity, write the first commit, tag a release, generate release notes, and finally wire the local folder to a remote. GitMe automates all of that while remaining transparent about what it does. It is idempotent by design, meaning you can run it repeatedly on the same folder without fear of corruption. If you need to overwrite an existing tag or force a re-initialisation, the `-Force` switch is there, but it never destroys work silently.

GitMe speaks PowerShell 5.1 natively. Every file is encoded in UTF-8 with BOM so that Windows PowerShell on legacy systems reads accents and special characters correctly. The module also runs flawlessly on PowerShell 7 and later, making it a safe choice for heterogeneous environments.

## What GitMe Does

When you invoke `gitme` inside a folder, the module first verifies that Git is installed and that its version is at least 2.50.0. It then resolves your identity, falling back gracefully from an explicit parameter to your global Git configuration and finally to your operating-system username. Next, it initialises the repository on the `main` branch, stages every file, creates a conventional initial commit, annotates a SemVer tag, and writes a `RELEASE_NOTES.md` file. If you asked for a remote, GitMe creates it through the provider API and pushes both the branch and the tag. If you prefer to keep things local, it can initialise a bare repository on a network path and point your working copy to it.

Version management follows SemVer and Conventional Commits. If you enable `-AutoBump`, GitMe inspects the commit history since the last tag and automatically increments the major, minor, or patch number based on whether it finds breaking changes, features, or fixes. This removes the guesswork from release preparation and keeps your changelog honest.

## Installation

You have four ways to bring GitMe onto your system, ordered from the quickest to the most integrated.

The fastest method is the one-liner installer. Open PowerShell and paste:

```powershell
irm https://raw.githubusercontent.com/yorgabr/GitMe/main/scripts/install.ps1 | iex
```

This downloads the latest release, verifies cryptographic checksums to guarantee that no byte was tampered with in transit, and drops the module into your user-scope PowerShell modules folder. After that, `Import-Module GitMe` makes the `Invoke-Gitme` function and its `gitme` alias available immediately.

If you already use the PowerShell Gallery, the module is published there as well:

```powershell
Install-Module -Name GitMe -Scope CurrentUser
```

For Windows users who prefer package managers, GitMe is listed on Winget:

```powershell
winget install YorgaBabuscan.GitMe
```

And for those who live in the Scoop ecosystem:

```powershell
scoop install gitme
```

Regardless of the method you choose, the installed code is protected. A SHA-256 checksum manifest is generated during packaging and verified at install time. If any file differs from the manifest, the installation aborts before a single command is imported. This ensures that the code running on your machine is exactly the code that passed the continuous-integration pipeline.

## Quick Start

Create a local repository with default settings:

```powershell
cd C:\Projects\MyNewApp
gitme -RepoName MyNewApp -VerboseOutput
```

Publish a public repository to GitHub:

```powershell
gitme -RepoName MyNewApp -Provider GitHub -CreateRemote -Token $env:GITHUB_TOKEN -VerboseOutput
```

Use GitLab instead:

```powershell
gitme -RepoName MyNewApp -Provider GitLab -CreateRemote -Token $env:GITLAB_TOKEN -VerboseOutput
```

Keep everything on your NAS:

```powershell
gitme -RepoName MyNewApp -Provider Local -RemotePath '\\nas\git' -VerboseOutput
```

Let GitMe decide the next version for you:

```powershell
gitme -RepoName MyNewApp -AutoBump -VerboseOutput
```

## Tab Completion

GitMe registers an argument completer for the `Provider` and `ApiBaseUrl` parameters. After importing the module, press `Tab` after `-Provider` and you will cycle through `GitHub`, `GitLab`, and `Local`. This works in both Windows PowerShell 5.1 and PowerShell 7.

## Architecture

The module is organised into small, single-purpose functions stored under `src/private` and `src/public`. The public surface consists of `Invoke-Gitme` and `Get-GitmeTabCompletion`. Everything else is an implementation detail that you can inspect, test, and mock. The native Git wrapper, `Invoke-GitMeNative`, is the secret to PowerShell 5.1 compatibility. It temporarily relaxes the error-action preference around every Git call, captures stderr as plain strings, and restores the caller's preference in a `finally` block. This eliminates the infamous `NativeCommandError` that would otherwise terminate the script whenever Git prints a hint to stderr.

The build pipeline is driven by Invoke-Build. Running `Invoke-Build` from the repository root executes formatting, linting, security analysis, testing, packaging, and optional publishing in a single dependency chain. The pipeline enforces one hundred percent code coverage; any pull request that drops below that threshold fails the build.

## Requirements

- Windows PowerShell 5.1 or PowerShell 7+
- Git 2.50.0 or later
- For remote creation on GitHub or GitLab, a personal access token with repository creation scope

## License

GitMe is free software released under the GNU General Public License version 3. You are welcome to use it, study it, share it, and improve it, provided that any distributed derivative work carries the same license. The full text is available in the `docs/LICENSE.md` file.

## Acknowledgements

This project was built with care for the Windows PowerShell 5.1 ecosystem that remains the backbone of countless enterprise automation stacks. Every design decision, from the BOM-encoded files to the error-handling strategy, reflects a commitment to reliability on the platforms where administrators actually work.
