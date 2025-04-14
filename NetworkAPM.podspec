Pod::Spec.new do |s|
  s.name             = 'NetworkAPM'
  s.version          = '0.1.0' # Initial version
  s.summary          = 'A network monitoring APM tool for iOS.'

  # This description is used to generate tags and improve search results.
  #   * Think: What does it do? Why did you write it? What is the focus?
  #   * Try to keep it short, snappy and to the point.
  #   * Write the description between the DESC delimiters below.
  #   * Finally, don't worry about the indent, CocoaPods strips it!
  s.description      = <<-DESC
                     A lightweight library to monitor iOS application network requests,
                     collecting timing metrics, status codes, errors, and traffic data.
                     It uses URLProtocol for interception and provides data for APM systems.
                     DESC

  s.homepage         = 'https://github.com/iOSAPMTools/iOSNetworkOPT' # Replace with your actual homepage URL
  # s.screenshots     = 'www.example.com/screenshots_1', 'www.example.com/screenshots_2'
  s.license          = { :type => 'MIT', :file => 'LICENSE' } # Assume MIT license, create a LICENSE file later
  s.author           = { 'Your Name or Org' => 'your.email@example.com' } # Replace with your details
  s.source           = { :git => 'https://github.com/iOSAPMTools/iOSNetworkOPT.git', :tag => s.version.to_s } # Replace with your repo URL
  # s.social_media_url = 'https://twitter.com/<TWITTER_USERNAME>'

  s.ios.deployment_target = '13.0' # Match the platform version in Package.swift
  s.swift_version = '5.5' # Match the Swift version in Package.swift

  s.source_files = 'NetworkAPM/**/*.swift' # Points to the source files

  # s.resource_bundles = {
  #   'NetworkAPM' => ['NetworkAPM/Assets/*.png']
  # }

  # s.public_header_files = 'Pod/Classes/**/*.h'
  s.frameworks = 'UIKit', 'Network' # Specify necessary system frameworks
  # s.dependency 'AFNetworking', '~> 2.3'
end 