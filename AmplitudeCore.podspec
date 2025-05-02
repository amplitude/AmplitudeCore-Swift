amplitude_core_version = "1.0.10" # Version is managed automatically by semantic-release, please don't change it manually

Pod::Spec.new do |s|
  s.name                   = "AmplitudeCore"
  s.version                = amplitude_core_version
  s.summary                = "Amplitude Core SDK"
  s.homepage               = "https://amplitude.com"
  s.license                = { :type => "MIT" }
  s.author                 = { "Amplitude" => "dev@amplitude.com" }
  s.source                 = { :git => "https://github.com/amplitude/AmplitudeCore-Swift.git", :tag => "v#{s.version}" }

  s.source_files           = 'Sources/AmplitudeCore/**/*.{h,swift}'
  s.resource_bundle        = { 'AmplitudeCore': ['Sources/AmplitudeCore/PrivacyInfo.xcprivacy'] }
  s.swift_version          = '5.9'

  s.ios.deployment_target  = '11.0'
  s.tvos.deployment_target = '11.0'
  s.osx.deployment_target  = '10.13'
  s.watchos.deployment_target  = '4.0'
  s.visionos.deployment_target = '1.0'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
