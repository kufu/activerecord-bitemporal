# Changelog

## Unreleased

### Breaking Changes

- [#15](https://github.com/kufu/activerecord-bitemporal/pull/15) - `validates :bitemporal_id, uniqueness: true` is no raise by default.

### Added

- [#15](https://github.com/kufu/activerecord-bitemporal/pull/15) - Added `.bitemporalize`. Use `.bitemporalize` instead of `include ActiveRecord::Bitemporal`.
- [#15](https://github.com/kufu/activerecord-bitemporal/pull/15) - Added `.bitemporalize` options.

| option | describe | default |
| --- | --- | --- |
| `enable_strict_by_validates_bitemporal_id` | raised with `validates :bitemporal_id, uniqueness: true` if `true` | false |


### Fixed

- None

### Deprecated

- None
