# Docs

How Stadig Lift and Stadig Macro work, and how to build them. Start with the [README](../README.md) for what the project is.

## See it

- [Screenshots](screenshots.md): both apps on iPhone, iPad, the Mac, Apple Vision Pro and Apple Watch.
- [The design](design.md): the palette, the numerals, the ruler, Your shape, and what each device is for.

## Build it

- [Building and running](building.md): what you need, the first build, everyday commands, running without a developer account.
- [Architecture](architecture.md): the ten packages, where code goes, how the two apps talk to each other, the identifiers.
- [Testing](testing.md), and [what the package tests cover](package-tests.md).
- [CI/CD](ci-cd.md): GitHub Actions, Xcode Cloud, branches and releases.

## How the apps work

- [Stadig Lift](lift.md): the shared core, the training engine and every screen, with its DEBUG launch arguments.
- [Stadig Macro](macro.md): logging, the phase plan, the catalogs and every screen, with its DEBUG launch arguments.
- [The shared container](shared-container.md): what the apps publish for each other, and the stats.
- [The food catalogs](../Apps/MacroTrack/Catalogs/README.md), and [their sources and licences](../Packages/FoodDatabase/Sources/FoodDatabase/Resources/ATTRIBUTION.md).

## Running the project

- [App Store Connect](app-store-connect.md): how the two apps are set up on the store.
- [The App Store listing](../Store/listing.md) and [its screenshots](../Store/README.md).
- [The website](../Site/README.md), stadig.dev.

## For coding agents

Stadig is built with coding agents (Claude Code). The rules they work to are in [CLAUDE.md](../CLAUDE.md), and the notes they keep as they go (the calls they made that need checking, and what was verified by hand) are in [agent-docs/](../agent-docs/README.md).
