### PR Commit Title Conventions

PR titles should follow [conventional commit standards](https://www.conventionalcommits.org/en/v1.0.0/).

#### Commit Types

- `feat(<optional scope>)`: New features (minimum minor release)
- `fix(<optional scope>)`: Bug fixes (minimum patch release)
- `perf(<optional scope>)`: Performance improvement
- `docs(<optional scope>)`: Documentation updates
- `test(<optional scope>)`: Test updates
- `refactor(<optional scope>)`: Code change that neither fixes a bug nor adds a feature
- `style(<optional scope>)`: Code style changes (e.g. formatting, commas, semicolons)
- `build(<optional scope>)`: Changes that affect the build system or external dependencies (e.g. Yarn, Npm)
- `ci(<optional scope>)`: Changes to our CI configuration files and scripts
- `chore(<optional scope>)`: Other changes that don't modify src or test files
- `revert(<optional scope>)`: Revert commit

### Public API and ABI changes

AmplitudeCore ships as a binary framework built with library evolution, and released closed-source binaries link it: Session Replay, Guides & Surveys, and the Amplitude-Swift xcframework zips. An app can pair an old release of any of them with a newer Core. CI (`.github/workflows/api-check.yml`) therefore compares every PR with the latest release using `swift-api-digester`. It fails on an ABI or API break of any public, `@_spi` or `@usableFromInline` declaration.

- Don't remove or change such a declaration. Renaming it, changing argument labels or types, or adding a parameter, even one with a default value, breaks binaries built against the last release. Add an overload instead and keep the old declaration, even if it is unused. A new protocol requirement needs a default implementation.
- If a break is intended and nothing depends on it, add the reported line, without `error: `, to `api/breakage-allowlist.txt` with a reason. Breaking public (non-`@_spi`) API also needs a major version (`feat!:`).
- `scripts/api/check.sh` runs the same check locally.
