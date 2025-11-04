## [1.2.4](https://github.com/amplitude/AmplitudeCore-Swift/compare/v1.2.3...v1.2.4) (2025-11-04)


### Bug Fixes

* add onReset plugin lifecycle handler ([#46](https://github.com/amplitude/AmplitudeCore-Swift/issues/46)) ([c9e3d39](https://github.com/amplitude/AmplitudeCore-Swift/commit/c9e3d3904bcd93186039fb2746a6ac24151f9f25))

## [1.2.3](https://github.com/amplitude/AmplitudeCore-Swift/compare/v1.2.2...v1.2.3) (2025-09-29)


### Bug Fixes

* prevent fetchRemoteTask was called before _updateConfigs finished ([#44](https://github.com/amplitude/AmplitudeCore-Swift/issues/44)) ([07ff742](https://github.com/amplitude/AmplitudeCore-Swift/commit/07ff742a760a2d1a9be7ad0c16420033a4519e24))

## [1.2.2](https://github.com/amplitude/AmplitudeCore-Swift/compare/v1.2.1...v1.2.2) (2025-08-22)


### Bug Fixes

* avoid supported version deprecated warning ([#41](https://github.com/amplitude/AmplitudeCore-Swift/issues/41)) ([313a8e9](https://github.com/amplitude/AmplitudeCore-Swift/commit/313a8e985a9939d4cb2378259027d60b96781855))

## [1.2.1](https://github.com/amplitude/AmplitudeCore-Swift/compare/v1.2.0...v1.2.1) (2025-08-14)


### Bug Fixes

* fix remote config key for ananlytics sdk ([#37](https://github.com/amplitude/AmplitudeCore-Swift/issues/37)) ([48a8318](https://github.com/amplitude/AmplitudeCore-Swift/commit/48a8318eeb0afdf3290ddc231672baec27be4b2f))
* include dSYM file for release ([#38](https://github.com/amplitude/AmplitudeCore-Swift/issues/38)) ([606b3d8](https://github.com/amplitude/AmplitudeCore-Swift/commit/606b3d83beda762221b509326e13f3afb755f491))

# [1.2.0](https://github.com/amplitude/AmplitudeCore-Swift/compare/v1.1.0...v1.2.0) (2025-08-01)


### Bug Fixes

* fix crash on iOS 14 ([#36](https://github.com/amplitude/AmplitudeCore-Swift/issues/36)) ([fb07835](https://github.com/amplitude/AmplitudeCore-Swift/commit/fb078354b11bbfd9204d413ae3bf0a79c8963603))


### Features

* use new remote config url scheme ([#32](https://github.com/amplitude/AmplitudeCore-Swift/issues/32)) ([37c537c](https://github.com/amplitude/AmplitudeCore-Swift/commit/37c537c53b3d15cbd3d9b4c0cb067cbd078b1d4e))

# [1.1.0](https://github.com/amplitude/AmplitudeCore-Swift/compare/v1.0.14...v1.1.0) (2025-06-26)


### Features

* add interface for ui change notification ([#31](https://github.com/amplitude/AmplitudeCore-Swift/issues/31)) ([e778a22](https://github.com/amplitude/AmplitudeCore-Swift/commit/e778a220a44d319e81744ac6d7d436a9524aa39c))

## [1.0.14](https://github.com/amplitude/AmplitudeCore-Swift/compare/v1.0.13...v1.0.14) (2025-06-17)


### Bug Fixes

* strip nil values from returned remote config responses ([#30](https://github.com/amplitude/AmplitudeCore-Swift/issues/30)) ([813a589](https://github.com/amplitude/AmplitudeCore-Swift/commit/813a58966f2fdefabd427c68110f9cfecc633696))

## [1.0.13](https://github.com/amplitude/AmplitudeCore-Swift/compare/v1.0.12...v1.0.13) (2025-06-03)


### Bug Fixes

* compile with Xcode 16.1 ([#28](https://github.com/amplitude/AmplitudeCore-Swift/issues/28)) ([13828a5](https://github.com/amplitude/AmplitudeCore-Swift/commit/13828a54d759d49c4de22a38ffc3b7910a3c38dc))

## [1.0.12](https://github.com/amplitude/AmplitudeCore-Swift/compare/v1.0.11...v1.0.12) (2025-05-12)


### Bug Fixes

* add plugin lookup by type ([#27](https://github.com/amplitude/AmplitudeCore-Swift/issues/27)) ([3e66ac8](https://github.com/amplitude/AmplitudeCore-Swift/commit/3e66ac8ec20c9ba6d3c658ec137369988f565370))
* allow warnings for cocoapods release ([#24](https://github.com/amplitude/AmplitudeCore-Swift/issues/24)) ([9fc6431](https://github.com/amplitude/AmplitudeCore-Swift/commit/9fc64312f50878c7259f7191f4ed22ef8608408c))
* restore carthage json again ([#25](https://github.com/amplitude/AmplitudeCore-Swift/issues/25)) ([5612efd](https://github.com/amplitude/AmplitudeCore-Swift/commit/5612efd34f92b1eea15d3b718fddb89e749665c7))
* use better supported file handling for jq in release script ([#26](https://github.com/amplitude/AmplitudeCore-Swift/issues/26)) ([ca2b488](https://github.com/amplitude/AmplitudeCore-Swift/commit/ca2b48886aa471e350358781b078fbeed59d5d09))

## [1.0.11](https://github.com/amplitude/AmplitudeCore-Swift/compare/v1.0.10...v1.0.11) (2025-05-09)


### Bug Fixes

* create framework before pod validation ([#23](https://github.com/amplitude/AmplitudeCore-Swift/issues/23)) ([a252824](https://github.com/amplitude/AmplitudeCore-Swift/commit/a25282486f04926a34099ff3863e65849589a475))
* restore deleted carthage manifest ([#21](https://github.com/amplitude/AmplitudeCore-Swift/issues/21)) ([6a5b373](https://github.com/amplitude/AmplitudeCore-Swift/commit/6a5b373ee5b9293fc4ee244787c2d4d25547c7f2))
* use binary framework for cocoapods ([#22](https://github.com/amplitude/AmplitudeCore-Swift/issues/22)) ([4c2cdfa](https://github.com/amplitude/AmplitudeCore-Swift/commit/4c2cdfa30277e9f5d04b01b08b3690040229615b))

## [1.0.10](https://github.com/amplitude/AmplitudeCore-Swift/compare/v1.0.9...v1.0.10) (2025-05-02)


### Bug Fixes

* add jitter to remote config retries ([#20](https://github.com/amplitude/AmplitudeCore-Swift/issues/20)) ([d4c9760](https://github.com/amplitude/AmplitudeCore-Swift/commit/d4c97601a0a8410c42ffffb4174f5ef6d2e4c915))
* cancel in-progress requests when RemoteConfigClient is deallocated ([#19](https://github.com/amplitude/AmplitudeCore-Swift/issues/19)) ([281a6b6](https://github.com/amplitude/AmplitudeCore-Swift/commit/281a6b63274fcd2032a4d2b48cdc2ddd4ad116bb))

## [1.0.9](https://github.com/amplitude/AmplitudeCore-Swift/compare/v1.0.8...v1.0.9) (2025-04-25)


### Bug Fixes

* build for maccataylst ([#18](https://github.com/amplitude/AmplitudeCore-Swift/issues/18)) ([e5e12d1](https://github.com/amplitude/AmplitudeCore-Swift/commit/e5e12d1742daf0755ccd872d2dd83158a080e464))

## [1.0.8](https://github.com/amplitude/AmplitudeCore-Swift/compare/v1.0.7...v1.0.8) (2025-04-22)


### Bug Fixes

* carthage - properly escape release and commit correct file ([#16](https://github.com/amplitude/AmplitudeCore-Swift/issues/16)) ([38b4315](https://github.com/amplitude/AmplitudeCore-Swift/commit/38b43157323af8fee22814004aa92d1d7dea79ed))

## [1.0.7](https://github.com/amplitude/AmplitudeCore-Swift/compare/v1.0.6...v1.0.7) (2025-04-22)


### Bug Fixes

* add carthage support via binary format ([#15](https://github.com/amplitude/AmplitudeCore-Swift/issues/15)) ([9855d70](https://github.com/amplitude/AmplitudeCore-Swift/commit/9855d706478c1094ef53de118726ba05b147061f))

## [1.0.6](https://github.com/amplitude/AmplitudeCore-Swift/compare/v1.0.5...v1.0.6) (2025-04-16)


### Bug Fixes

* Empty Commit to Trigger a Build ([e4d7eac](https://github.com/amplitude/AmplitudeCore-Swift/commit/e4d7eaca621e739b1102a5429b5556c237638688))

## [1.0.5](https://github.com/amplitude/AmplitudeCore-Swift/compare/v1.0.4...v1.0.5) (2025-04-15)


### Bug Fixes

* add podspec ([#14](https://github.com/amplitude/AmplitudeCore-Swift/issues/14)) ([5d349a6](https://github.com/amplitude/AmplitudeCore-Swift/commit/5d349a6fa6e5782db151a3982639f7ef3a7309e1))

## [1.0.4](https://github.com/amplitude/AmplitudeCore-Swift/compare/v1.0.3...v1.0.4) (2025-04-15)


### Bug Fixes

* add sendable conformance to logger protocols ([#13](https://github.com/amplitude/AmplitudeCore-Swift/issues/13)) ([3300da8](https://github.com/amplitude/AmplitudeCore-Swift/commit/3300da8f34e15aca309a227612bbe9e0c7bcb68b))

## [1.0.3](https://github.com/amplitude/AmplitudeCore-Swift/compare/v1.0.2...v1.0.3) (2025-04-10)


### Bug Fixes

* generate objc modulemap ([#12](https://github.com/amplitude/AmplitudeCore-Swift/issues/12)) ([35f3a6b](https://github.com/amplitude/AmplitudeCore-Swift/commit/35f3a6b31ab0981fed0f679efd5dabb3cecf7538))

## [1.0.2](https://github.com/amplitude/AmplitudeCore-Swift/compare/v1.0.1...v1.0.2) (2025-04-09)


### Bug Fixes

* refactor plugins ([#5](https://github.com/amplitude/AmplitudeCore-Swift/issues/5)) ([e5c11bb](https://github.com/amplitude/AmplitudeCore-Swift/commit/e5c11bb9f2ab318c36faa321490a480ebdbab9b8))

## [1.0.1](https://github.com/amplitude/AmplitudeCore-Swift/compare/v1.0.0...v1.0.1) (2025-03-28)


### Bug Fixes

* add binary AmpitudeCoreFramework product ([#10](https://github.com/amplitude/AmplitudeCore-Swift/issues/10)) ([5683e0b](https://github.com/amplitude/AmplitudeCore-Swift/commit/5683e0b9f6cf24e492eac47d4562bd505aa34cc9))

# 1.0.0 (2025-03-25)


### Bug Fixes

* add privacy info ([#4](https://github.com/amplitude/AmplitudeCore-Swift/issues/4)) ([2aa6475](https://github.com/amplitude/AmplitudeCore-Swift/commit/2aa647584cc76dbb8104dc6028847272894f5ade))
* support xcode 15.2 compilation ([#9](https://github.com/amplitude/AmplitudeCore-Swift/issues/9)) ([68c31f8](https://github.com/amplitude/AmplitudeCore-Swift/commit/68c31f894e02006e258e4dd3ac431bae7c81936f))
