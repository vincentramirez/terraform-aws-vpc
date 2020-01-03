
# Change Log
## [v0.0.2] - 2019-07-19

- Updated the vpc-flowlog role permissions to allow logs:PutSubscriptionFilter


## [v1.1.1] - 2019-04-03
### Changed
- Removed old references to cloudcraft from module source

## [v1.1.0] - 2019-01-31
### Added
- Set the DHCP options to true by default
- Set DNS servers to "10.64.48.7" and "10.64.50.7"
- Set the DNS suffix to "aws.xyz.abc.com"
- Set DNS Hostnames to true by default

## [v1.0.5] - 2019-01-10
### Fixed
Removed role entry for CloudWatch subscription filter that was causing an error

## [v1.0.4] - 2019-01-09
### Added
Added the CloudWatch log subscription to forward VPC Flowlogs to Central Logging account
### Fixed
Changed deprecated log_group_name to log_destination for aws_flow_log resource

## [v1.0.3] - 2018-10-30
### Changed
Corrected the sid of the policy document used by FlowLogs

## [v1.0.2] - 2018-10-23
### Added
Enable flowlogs for the vpc by default

## [v1.0.1] - 2018-10-23
### Added
Initial release.

## [v1.0.0] - 2018-10-06
### Added
This is [v1.46.0](https://github.com/terraform-aws-modules/terraform-aws-vpc/releases/tag/v1.46.0) of the public vpc module.

The format is based on [Keep a Changelog][changelog] and this project adheres
to [Semantic Versioning][semver].

<!-- Links -->
[changelog]:http://keepachangelog.com
[semver]:http://semver.org
