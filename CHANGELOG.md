# Changelog

## 6.1.0

### Breaking Changed

### Added

- [Support GlobalID integration #176](https://github.com/kufu/activerecord-bitemporal/pull/176)

### Changed

- [Add explicit activesupport dependency #208](https://github.com/kufu/activerecord-bitemporal/pull/208)
- [Improve ValidDatetimeRangeError message with better grammar and context #207](https://github.com/kufu/activerecord-bitemporal/pull/207)
- [Delay execution of ActiveRecord::Base-related processing #189](https://github.com/kufu/activerecord-bitemporal/pull/189)

### Deprecated

### Removed

### Fixed

### Chores

- [Bump ruby/setup-ruby from 1.263.0 to 1.265.0 #223](https://github.com/kufu/activerecord-bitemporal/pull/223)
- [Update gemspec files to avoid using git #222](https://github.com/kufu/activerecord-bitemporal/pull/222)
- [Bump ruby/setup-ruby from 1.257.0 to 1.263.0 #221](https://github.com/kufu/activerecord-bitemporal/pull/221)
- [Add CodeSpell workflow for spell checking in pull requests #220](https://github.com/kufu/activerecord-bitemporal/pull/220)
- [Configure dependabot cooldown period to 3 days #219](https://github.com/kufu/activerecord-bitemporal/pull/219)
- [Bump ruby/setup-ruby from 1.255.0 to 1.257.0 #218](https://github.com/kufu/activerecord-bitemporal/pull/218)
- [Bump actions/checkout from 4.2.2 to 5.0.0 #215](https://github.com/kufu/activerecord-bitemporal/pull/215)
- [Bump ruby/setup-ruby from 1.254.0 to 1.255.0 #214](https://github.com/kufu/activerecord-bitemporal/pull/214)
- [Bump ruby/setup-ruby from 1.247.0 to 1.254.0 #213](https://github.com/kufu/activerecord-bitemporal/pull/213)
- [Bump ruby/setup-ruby from 1.247.0 to 1.253.0 #212](https://github.com/kufu/activerecord-bitemporal/pull/212)
- [Setup RuboCop #211](https://github.com/kufu/activerecord-bitemporal/pull/211)
- [Bump ruby/setup-ruby from 1.245.0 to 1.247.0 #210](https://github.com/kufu/activerecord-bitemporal/pull/210)
- [Using Trusted Publishing for RubyGems.org. #209](https://github.com/kufu/activerecord-bitemporal/pull/209)
- [Bump ruby/setup-ruby from 1.244.0 to 1.245.0 #206](https://github.com/kufu/activerecord-bitemporal/pull/206)

## 6.0.0

### Breaking Changed

- [Add Ruby 3.4 and remove Ruby 3.0 in CI #185](https://github.com/kufu/activerecord-bitemporal/pull/185)
- [Drop support Rails 6.1 #192](https://github.com/kufu/activerecord-bitemporal/pull/192)

### Added

- [CI against Rails 7.2 #164](https://github.com/kufu/activerecord-bitemporal/pull/164)
- [Support custom column names for valid time in .bitemporalize #200](https://github.com/kufu/activerecord-bitemporal/pull/200)

### Changed

### Deprecated

### Removed

### Fixed

- [Prevent where clauses from ignored by `ignore_valid_datetime` #190](https://github.com/kufu/activerecord-bitemporal/pull/190)

### Chores

- [Add a note to the README that PostgreSQL is required to run the tests. #188](https://github.com/kufu/activerecord-bitemporal/pull/188)
- [Remove specs for Rails 5.x #191](https://github.com/kufu/activerecord-bitemporal/pull/191)
- [Update auto assign member #193](https://github.com/kufu/activerecord-bitemporal/pull/193)
- [Pin GitHub Actions dependencies to specific commit hashes #194](https://github.com/kufu/activerecord-bitemporal/pull/194)
- [Bump ruby/setup-ruby from 1.227.0 to 1.229.0 #195](https://github.com/kufu/activerecord-bitemporal/pull/195)
- [Bump ruby/setup-ruby from 1.229.0 to 1.233.0 #197](https://github.com/kufu/activerecord-bitemporal/pull/197)
- [Bump ruby/setup-ruby from 1.233.0 to 1.235.0 #198](https://github.com/kufu/activerecord-bitemporal/pull/198)
- [Bump ruby/setup-ruby from 1.235.0 to 1.237.0 #199](https://github.com/kufu/activerecord-bitemporal/pull/199)
- [Bump ruby/setup-ruby from 1.237.0 to 1.238.0 #201](https://github.com/kufu/activerecord-bitemporal/pull/201)
- [Bump ruby/setup-ruby from 1.238.0 to 1.242.0 #202](https://github.com/kufu/activerecord-bitemporal/pull/202)
- [Bump ruby/setup-ruby from 1.242.0 to 1.244.0 #203](https://github.com/kufu/activerecord-bitemporal/pull/203)
- [Update auto assign member #204](https://github.com/kufu/activerecord-bitemporal/pull/204)

## 5.3.0

### Added

### Changed

- [Replace `default` overrides from `load_schema!` to `attribute` #172](https://github.com/kufu/activerecord-bitemporal/pull/172)
- [`Or` node changed to `Nary` in Rails 7.2 #173](https://github.com/kufu/activerecord-bitemporal/pull/173)
- [Exclude record valid range end in uniqueness validation #184](https://github.com/kufu/activerecord-bitemporal/pull/184)

### Deprecated

### Removed

### Fixed

### Chores

- [Add specs under specific conditions #171](https://github.com/kufu/activerecord-bitemporal/pull/171)
- [Add Dependabot for GitHub Actions #174](https://github.com/kufu/activerecord-bitemporal/pull/174)
- [Bump actions/checkout from 3 to 4 #175](https://github.com/kufu/activerecord-bitemporal/pull/175)
- [Replace CircleCI with GitHub Actions #177](https://github.com/kufu/activerecord-bitemporal/pull/177)
- [Update README as `within_deleted` and `without_deleted` are deprecated #178](https://github.com/kufu/activerecord-bitemporal/pull/178)
- [Fix typo #181](https://github.com/kufu/activerecord-bitemporal/pull/181)
- [Fix #force_update block comment #183](https://github.com/kufu/activerecord-bitemporal/pull/183)
- [Support Docker Compose V2 #186](https://github.com/kufu/activerecord-bitemporal/pull/186)

## 5.2.0

### Added

### Changed

### Deprecated

### Removed

### Fixed

- [Delegate CollectionProxy#bitemporal_value to Relation #168](https://github.com/kufu/activerecord-bitemporal/pull/168)
- [Fix unintended valid_datetime set when `CollectionProxy#load` #169](https://github.com/kufu/activerecord-bitemporal/pull/169)

### Chores

- [Do not run CI against rails_main #166](https://github.com/kufu/activerecord-bitemporal/pull/166)

## 5.1.0

### Added

### Changed

### Deprecated

### Removed

### Fixed

- [Remove `joinable: false` #156](https://github.com/kufu/activerecord-bitemporal/pull/156)

### Chores

- [Remove database_cleaner #162](https://github.com/kufu/activerecord-bitemporal/pull/162)

## 5.0.1

- [Fix a typo #157](https://github.com/kufu/activerecord-bitemporal/pull/157)
- [Remove unneeded unscope values #159](https://github.com/kufu/activerecord-bitemporal/pull/159)
- [Remove unused `without_ignore` option #160](https://github.com/kufu/activerecord-bitemporal/pull/160)
- [update auto assign #161](https://github.com/kufu/activerecord-bitemporal/pull/161)

## 5.0.0

### Breaking Changed

- [CI against Ruby 3.2, 3.3, Drop Ruby 2.7 and Rails 6.0 #150](https://github.com/kufu/activerecord-bitemporal/pull/150)

### Added

- [Support date type of valid time #149](https://github.com/kufu/activerecord-bitemporal/pull/149)
- [Add support Rails 7.1 #151](https://github.com/kufu/activerecord-bitemporal/pull/151)
- [Add Persistence#bitemporal_at and ActiveRecord::Bitemporal.bitemporal_at #152](https://github.com/kufu/activerecord-bitemporal/pull/152)

### Changed

### Deprecated

### Removed

### Fixed

- [Fix deleted time order between associations #154](https://github.com/kufu/activerecord-bitemporal/pull/154)

### Chores

- [Don't use appraisal in CI #145](https://github.com/kufu/activerecord-bitemporal/pull/145)
- [Remove code for Active Record 6.0 #153](https://github.com/kufu/activerecord-bitemporal/pull/153)

## 4.3.0

### Added

- [Add `previously_force_updated?` #142](https://github.com/kufu/activerecord-bitemporal/pull/142)

### Changed

### Deprecated

### Removed

### Fixed

### Chores

- [Remove unneeded spec for Rails 5.x #143](https://github.com/kufu/activerecord-bitemporal/pull/143)

## 4.2.0

### Added

- [Allow passing `operated_at` to destroy #138](https://github.com/kufu/activerecord-bitemporal/pull/138)

### Changed

- [Change not to create history when destroying with `force_update` #135](https://github.com/kufu/activerecord-bitemporal/pull/135)
- [Raise `ValidDatetimeRangeError` instead of `RecordInvalid` in `_update_row` #136](https://github.com/kufu/activerecord-bitemporal/pull/136)

### Deprecated

### Removed

### Fixed

### Chores

- [Fix for RSpec deprecated warning #132](https://github.com/kufu/activerecord-bitemporal/pull/132)
- [Add some files to .gitignore #134](https://github.com/kufu/activerecord-bitemporal/pull/134)

## 4.1.0

### Added
- [add label option #127](https://github.com/kufu/activerecord-bitemporal/pull/127)

### Changed
- [Support for inverse_of of Rails 6.1 or higher #130](https://github.com/kufu/activerecord-bitemporal/pull/130)

### Deprecated

### Removed

### Fixed

## 4.0.0

### Breaking Changed

- [[proposal]When bitemporal_at exists inside the nest, the specified date was not prioritized, so the date of the inner bitemporal_at is now prioritized. #121](https://github.com/kufu/activerecord-bitemporal/pull/121)
- [Drop support Rails 5.2 #122](https://github.com/kufu/activerecord-bitemporal/pull/122)
- [Add required_ruby_version >= 2.7.0 #125](https://github.com/kufu/activerecord-bitemporal/pull/125)

### Added

- [Add support `bitemporal_callbacks` #123](https://github.com/kufu/activerecord-bitemporal/pull/123)

  ```rb
  class Employee < ActiveRecord::Base
    include ActiveRecord::Bitemporal
  
    after_bitemporal_create :log_create
    after_bitemporal_update :log_update
    after_bitemporal_destroy :log_destroy
  
    private
    
    def log_create
      puts "employee created"
    end

    def log_update
      puts "employee updated"
    end

    def log_destroy
      puts "employee destroyed"
    end
  end
  
  employee = Employee.create!(...) # => "employee created"
  employee.update!(...) # => "employee updated"
  employee.destroy! # => "employee destroyed"
  ```

### Changed

- [Update auto asgn #124](https://github.com/kufu/activerecord-bitemporal/pull/124)
- [Update License and CoC files #115](https://github.com/kufu/activerecord-bitemporal/pull/115)

### Deprecated

### Removed

- [Remove Gemfile.lock #126](https://github.com/kufu/activerecord-bitemporal/pull/126)
- [Remove test cases for using bitemporal_option_merge! of ActiveRecord:::Bitemporal::Callbacks #129](https://github.com/kufu/activerecord-bitemporal/pull/129)

### Fixed


## 3.0.0

### Breaking Changed
- [Assign updated bitemporal times to the receiver after update/destroy](https://github.com/kufu/activerecord-bitemporal/pull/118)

### Added

### Changed

### Deprecated

### Removed

### Fixed

## 2.3.0

### Breaking Changed

### Added
- [Add `InstanceMethods#swapped_id_previously_was`](https://github.com/kufu/activerecord-bitemporal/pull/114)

### Changed

### Deprecated

### Removed

### Fixed

## 2.2.0

### Breaking Changed

### Added
- [replace postgres docker image](https://github.com/kufu/activerecord-bitemporal/pull/103)
- [use Matrix Jobs in CircleCI](https://github.com/kufu/activerecord-bitemporal/pull/107)
- [Add support changing swapped_id, when called #destroy](https://github.com/kufu/activerecord-bitemporal/pull/110)

### Changed

### Deprecated

### Removed

### Fixed

## 2.1.0

### Breaking Changed

### Added
- [Update valid_to after #update](https://github.com/kufu/activerecord-bitemporal/pull/105)
- [Add GitHub Actions workflow to release to RubyGems.org](https://github.com/kufu/activerecord-bitemporal/pull/104)
- [migrate Scheduled workflows in CircleCI](https://github.com/kufu/activerecord-bitemporal/pull/106)

### Changed

### Deprecated

### Removed

### Fixed

## 2.0.0

### Breaking Changed
- [[Proposal] Changed valid_in to exclude valid_from = to and valid_to = from. by osyo-manga · Pull Request #95](https://github.com/kufu/activerecord-bitemporal/pull/95)

### Added

### Changed
- [[Proposal] Add range argument to .valid_allin. by Dooor · Pull Request #98](https://github.com/kufu/activerecord-bitemporal/pull/98)

### Deprecated

### Removed

### Fixed
- [Fix JOIN query does not have valid_from / valid_to when using .or. by osyo-manga · Pull Request #99](https://github.com/kufu/activerecord-bitemporal/pull/99)
- [Fix typo in README.md by Naoya9922 · Pull Request #101](https://github.com/kufu/activerecord-bitemporal/pull/101)

## 1.1.0

### Added

- [Add bitemporal data structure visualizer by wata727 · Pull Request #94](https://github.com/kufu/activerecord-bitemporal/pull/94)

### Changed

### Deprecated

### Removed

### Fixed

## 1.0.0

First stable release
