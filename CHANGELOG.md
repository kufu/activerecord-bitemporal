# Changelog

## Unreleased

### Breaking Changes

- None

### Added

- [#12](https://github.com/kufu/activerecord-bitemporal/pull/12) - Added utility (and extension) scopes.
  - `.bitemporl_for(id)`
  - `.valid_in(from: from, to: to)`
  - `.valid_allin(from: from, to: to)`
  - `.bitemporal_histories_by(id)`
  - `.bitemporal_most_future(id)`
  - `.bitemporal_most_past(id)`

### Fixed

- None

### Deprecated

- None
