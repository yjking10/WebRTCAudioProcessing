#
# Be sure to run `pod lib lint WebRTCAudioProcessing.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'WebRTCAudioProcessing'
  s.version          = '1.0.4'
  s.summary          = 'A short description of WebRTCAudioProcessing.'

# This description is used to generate tags and improve search results.
#   * Think: What does it do? Why did you write it? What is the focus?
#   * Try to keep it short, snappy and to the point.
#   * Write the description between the DESC delimiters below.
#   * Finally, don't worry about the indent, CocoaPods strips it!

  s.description      = <<-DESC
TODO: Add long description of the pod here.
                       DESC

  s.homepage         = 'https://github.com/yjking10/WebRTCAudioProcessing'
  # s.screenshots     = 'www.example.com/screenshots_1', 'www.example.com/screenshots_2'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'yjking10' => 'yj_king10@163.com' }
  s.source           = { :git => 'https://github.com/yjking10/WebRTCAudioProcessing.git', :tag => s.version.to_s }
  # s.social_media_url = 'https://twitter.com/<TWITTER_USERNAME>'

  s.ios.deployment_target = '12.0'

  s.source_files = 'WebRTCAudioProcessing/Classes/**/*.{h,m,mm}'
  # ✅ 2. 声明公共头文件（让外部能 #import "AudioProcessingWrapper.h"）
   s.public_header_files = 'WebRTCAudioProcessing/Classes/**/*.h'
   s.vendored_libraries = 'WebRTCAudioProcessing/audio_processing/lib/libwebrtc-audio-processing-2.a'

   # ✅ 保留整个 audio_processing 目录（关键！）
  s.preserve_paths = 'WebRTCAudioProcessing/audio_processing/**/*'
    s.static_framework = true


  s.libraries = ['icucore', 'c++', 'bz2', 'z', 'iconv']
  s.pod_target_xcconfig = {
    'OTHER_LDFLAGS' => '-ObjC -lc++',
     'HEADER_SEARCH_PATHS' => '$(inherited) "$(PODS_TARGET_SRCROOT)/WebRTCAudioProcessing/audio_processing/include" "$(PODS_TARGET_SRCROOT)/WebRTCAudioProcessing/audio_processing/include/webrtc-audio-processing-2"',
      'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
  'CLANG_CXX_LIBRARY' => 'libc++',
    # 'DEFINES_MODULE' => 'YES',
       'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'arm64', # 排除所有模拟器架构
       }
  
  
#  s.header_mappings_dir = 'WebRTCAudioProcessing/audio_processing/include'

  
  # s.resource_bundles = {
  #   'WebRTCAudioProcessing' => ['WebRTCAudioProcessing/Assets/*.png']
  # }

  # s.public_header_files = 'Pod/Classes/**/*.h'
  # s.frameworks = 'UIKit', 'MapKit'
  # s.dependency 'AFNetworking', '~> 2.3'
end
