# Contributing to GitMe

Thank you for considering a contribution to GitMe. This document exists so that anyone, even if you have never submitted a pull request before, can move from an idea to a merged change with confidence. Read it once, keep it open while you work, and do not hesitate to ask questions in an issue if anything feels unclear.

## Philosophy

GitMe treats every user as a potential contributor. The codebase is intentionally small and modular so that a single afternoon is enough to understand the full flow. We value correctness over cleverness, clarity over brevity, and kindness over speed. If you fix a bug, add a feature, or improve a comment, you are already part of the project.

## Before You Write Code

The first step is always communication. Open an issue on GitHub describing what you want to achieve. If you found a bug, include the exact command you ran, the error message, and your PowerShell and Git versions. If you want a new feature, explain the use case: who needs it, why the current behaviour is insufficient, and how you imagine it working. A well-written issue saves hours of review later.

If an issue already exists and you want to claim it, leave a comment saying you are working on it. This prevents duplicate effort and lets maintainers offer guidance early.

## Setting Up Your Environment

You need a Windows machine with PowerShell 5.1 or PowerShell 7, Git 2.50.0 or newer, and an internet connection. Fork the repository on GitHub, then clone your fork locally:

```powershell
git clone https://github.com/YOUR_USERNAME/GitMe.git
cd GitMe
```

Install the build dependencies by running the bootstrap script. This script checks for Invoke-Build, Pester, PSScriptAnalyzer, and the other modules required by the pipeline, installing anything that is missing:

```powershell
.\.build\dependencies.ps1
```

If the script reports that everything is already installed, you are ready. If it installs new modules, you may need to restart your PowerShell session so that the module paths refresh.

## Understanding the Layout

The repository is organised so that every file has a single, obvious home. The `src` folder contains the module itself. Inside `src`, `GitMe.psd1` is the manifest that PowerShell reads when you import the module, and `GitMe.psm1` is the root module that loads everything else. The `src/private` folder holds helper functions that users never call directly, such as the Git wrapper, the logging utility, and the remote-repository creators. The `src/public` folder holds the two functions that are exported: `Invoke-Gitme` and `Get-GitmeTabCompletion`. If you add a new feature, ask yourself whether it is part of the public surface or an internal detail, and place the file accordingly.

The `tests` folder mirrors the source structure. `Module.Tests.ps1` verifies that the module loads and that the private helpers behave correctly in isolation. `Functions.Tests.ps1` exercises the business logic with every branch mocked. `Invoke-Gitme.Tests.ps1` treats the public function as a black box, ensuring that the orchestration works end to end. When you add a new function, add a corresponding `Describe` block in the appropriate test file.

The `.build` folder contains the Invoke-Build tasks, the PSScriptAnalyzer settings, the dependency bootstrapper, and the version-bump script. You rarely need to touch these files unless you are changing the pipeline itself.

The `scripts` folder holds the one-line installer that users download with `irm ... | iex`. The `manifests` folder contains the Winget and Scoop package definitions. The `docs` folder is where this file, the license, and the readme live.

## Making a Change

Create a branch from the latest `main` with a descriptive name. Use the Conventional Commits convention for your branch name as well, so that reviewers immediately understand the intent:

```powershell
git checkout -b feat/add-gitlab-group-support
```

Write your code in small, focused commits. Each commit should do one thing and do it completely. If you are fixing a bug and also refactoring a nearby function, split those into two commits. This makes review faster and rollback safer.

Every commit message must follow the Conventional Commits specification. Start with a type, optionally followed by a scope in parentheses, then a colon and a space, then a short imperative description:

```
feat(remote): add support for GitLab subgroups
fix(wrapper): prevent null reference when git is missing
docs(readme): clarify Winget installation steps
```

If your change introduces a breaking change, append a `!` after the type or scope, or include a `BREAKING CHANGE:` footer in the commit body. The automated version bumper reads these markers and increments the major version accordingly.

## Running the Build Locally

Before pushing anything, run the full build on your machine. From the repository root, type:

```powershell
Invoke-Build
```

This executes the default task chain: Clean, Format, Analyze, Security, Test, Build, and Package. If any step fails, the build stops and tells you exactly what went wrong. Fix the issue, run `Invoke-Build` again, and repeat until everything is green.

The Test task is especially strict. It runs every test in the `tests` folder and measures code coverage. If any line of your new code is not exercised by a test, the build fails. This is not bureaucracy; it is how we guarantee that the module behaves predictably on every supported platform. Write a test for every logical branch, including error paths. Use Pester's `Mock` command to replace external dependencies such as `git`, `Invoke-RestMethod`, and filesystem cmdlets. This keeps the suite fast and deterministic.

If you changed formatting, the Format task may modify files in place. Review those changes with `git diff` and commit them separately so that the diff remains readable.

## Writing Tests

Tests in this project use Pester 5. Place them inside a `Describe` block named after the function under test. Use `BeforeAll` to dot-source the module and `BeforeEach` to reset mocks and script-scope variables. Every `It` block should contain a single assertion or a tightly related group of assertions about one behaviour.

When you mock a command, prefer `ParameterFilter` over broad mocks. This ensures that your test verifies not only that the command was called, but that it was called with the correct arguments. If you need to capture an argument for later inspection, assign it to a script-scope variable inside the mock script block.

If your change touches the public `Invoke-Gitme` function, add an integration test in `Invoke-Gitme.Tests.ps1`. These tests mock the entire dependency graph and verify that the orchestration calls each helper in the right order with the right parameters.

## Submitting Your Change

Push your branch to your fork and open a pull request against the upstream `main` branch. The pull-request template will ask for a summary, a list of changes, and a checklist. Fill it out honestly. The checklist includes items such as "I ran Invoke-Build locally and it passed" and "I added tests for every new line of code." These are not suggestions; they are requirements.

Once the pull request is open, the continuous-integration pipeline will run on GitHub Actions. It repeats the same steps you ran locally, but on a clean Windows runner, ensuring that your change does not depend on anything specific to your machine. If the pipeline fails, click into the logs, read the error, fix it, and push again. There is no shame in a red build; every contributor has been there.

A maintainer will review your pull request as soon as possible. Reviewers may ask questions, request changes, or suggest alternatives. This is a conversation, not an interrogation. Respond to each comment, either by making the requested change or by explaining why you chose a different approach. Once the reviewer is satisfied and the pipeline is green, your change will be merged.

After merge, the version-bump job on the main branch will read your Conventional Commits, determine the next SemVer, update the manifest, tag the repository, and trigger the release pipeline. Your contribution will appear in the next release automatically.

## Code of Conduct

Treat everyone with respect. Harassment, discrimination, and aggressive behaviour are not tolerated. If you see something that violates this standard, contact the maintainers privately. We are here to build useful software together, and that requires a safe, welcoming environment for people of all backgrounds and experience levels.

## Getting Help

If you are stuck at any point, open an issue with the label `question`. Describe what you tried, what you expected, and what happened instead. The community monitors these issues and will help you move forward. There are no stupid questions, only unanswered ones.
