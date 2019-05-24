# Changelog

## Unreleased

### Breaking Changes

- [#15](https://github.com/kufu/activerecord-bitemporal/pull/15) - `validates :bitemporal_id, uniqueness: true` is no raise by default.
- [#19](https://github.com/kufu/activerecord-bitemporal/pull/19) - Fix create history records after logical destroy in #destroy.

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

- [#17](https://github.com/kufu/activerecord-bitemporal/pull/17) - Fixed bug in create record with valid_datetime out of the range valid_from to valid_to.
- [#18](https://github.com/kufu/activerecord-bitemporal/pull/18) - `record.valid_datetime` is not nil when after `Model.valid_at("2019/1/1").ignore_valid_datetime`.
- [#18](https://github.com/kufu/activerecord-bitemporal/pull/18) - `ignore_valid_datetime` is not applied in `ActiveRecord::Bitemporal.valid_at!`.
- [#21](https://github.com/kufu/activerecord-bitemporal/pull/21) - Fixed bug in multi thread with `#update`.
- [#24](https://github.com/kufu/activerecord-bitemporal/pull/24) [#25](https://github.com/kufu/activerecord-bitemporal/pull/25) - Fixed bug. Does not respect table alias on join clause.
- [#27](https://github.com/kufu/activerecord-bitemporal/pull/27) - Fixed a bug that `swapped_id` doesn't change after `#reload`.
- [#28](https://github.com/kufu/activerecord-bitemporal/pull/28) - Fix the bug that `valid_from == valid_to` record is generated.

### Deprecated

- None
