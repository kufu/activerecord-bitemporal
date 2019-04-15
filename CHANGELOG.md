# Changelog

## Unreleased

### Breaking Changes

- [#15](https://github.com/kufu/activerecord-bitemporal/pull/15) - `validates :bitemporal_id, uniqueness: true` is no raise by default.

### Added

- [#12](https://github.com/kufu/activerecord-bitemporal/pull/12) - Added utility (and extension) scopes.
  - `.bitemporl_for(id)`
  - `.valid_in(from: from, to: to)`
  - `.valid_allin(from: from, to: to)`
  - `.bitemporal_histories_by(id)`
  - `.bitemporal_most_future(id)`
  - `.bitemporal_most_past(id)`
- [#15](https://github.com/kufu/activerecord-bitemporal/pull/15) - Added `.bitemporalize`. Use `.bitemporalize` instead of `include ActiveRecord::Bitemporal`.
- [#15](https://github.com/kufu/activerecord-bitemporal/pull/15) - Added `.bitemporalize` options.

| option | describe | default |
| --- | --- | --- |
| `enable_strict_by_validates_bitemporal_id` | raised with `validates :bitemporal_id, uniqueness: true` if `true` | false |


### Fixed

- [#18](https://github.com/kufu/activerecord-bitemporal/pull/18) - `record.valid_datetime` is not nil when after `Model.valid_at("2019/1/1").ignore_valid_datetime`.
- [#18](https://github.com/kufu/activerecord-bitemporal/pull/18) - `ignore_valid_datetime` is not applied in `ActiveRecord::Bitemporal.valid_at!`.

### Deprecated

- None
