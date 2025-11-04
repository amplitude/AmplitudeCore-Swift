amplitude_core_version = "1.2.4" # Version is managed automatically by semantic-release, please don't change it manually

Pod::Spec.new do |s|
  s.name                   = "AmplitudeCore"
  s.version                = amplitude_core_version
  s.summary                = "Amplitude Core SDK"
  s.homepage               = "https://amplitude.com"
  s.license                = { :type => "MIT" }
  s.author                 = { "Amplitude" => "dev@amplitude.com" }

  s.ios.deployment_target  = '11.0'
  s.tvos.deployment_target = '11.0'
  s.osx.deployment_target  = '10.13'
  s.watchos.deployment_target  = '4.0'
  s.visionos.deployment_target = '1.0'

  s.source                 = { :http => "https://github.com/amplitude/AmplitudeCore-Swift/releases/download/v#{amplitude_core_version}/AmplitudeCore.zip" }
  s.vendored_frameworks    = "AmplitudeCore.xcframework"
end
