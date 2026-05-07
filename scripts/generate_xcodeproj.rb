#!/usr/bin/env ruby

require 'fileutils'
require 'xcodeproj'

ROOT = File.expand_path('..', __dir__)
PROJECT_PATH = File.join(ROOT, 'Record.xcodeproj')
APP_TARGET_NAME = 'Record'
CORE_TARGET_NAME = 'RecordCore'
TEST_TARGET_NAME = 'RecordCoreTests'
PRODUCT_BUNDLE_IDENTIFIER = 'com.shaofeizhi.record'

FileUtils.rm_rf(PROJECT_PATH)

project = Xcodeproj::Project.new(PROJECT_PATH)
project.root_object.attributes['LastSwiftUpdateCheck'] = '2620'
project.root_object.attributes['LastUpgradeCheck'] = '2620'

core_target = project.new_target(:framework, CORE_TARGET_NAME, :osx, '14.0')
app_target = project.new_target(:application, APP_TARGET_NAME, :osx, '14.0')
test_target = project.new_target(:unit_test_bundle, TEST_TARGET_NAME, :osx, '14.0')
app_target.add_dependency(core_target)
test_target.add_dependency(core_target)

frameworks_group = project.frameworks_group
%w[
  AppKit.framework
  AVFoundation.framework
  CoreImage.framework
  Vision.framework
  UniformTypeIdentifiers.framework
].each do |framework|
  path = "System/Library/Frameworks/#{framework}"
  file_ref = frameworks_group.files.find { |file| file.path == path } || frameworks_group.new_file(path)
  app_target.frameworks_build_phase.add_file_reference(file_ref, true)
end

tests_group = project.main_group.find_subpath('Tests', true)
sources_group = project.main_group.find_subpath('Sources', true)

core_group = sources_group.find_subpath('RecordCore', true)
Dir[File.join(ROOT, 'Sources/RecordCore/**/*.swift')].sort.each do |path|
  relative_path = Pathname.new(path).relative_path_from(Pathname.new(ROOT)).to_s
  file_ref = core_group.new_file(relative_path)
  core_target.add_file_references([file_ref])
end

app_group = sources_group.find_subpath('RecordApp', true)
Dir[File.join(ROOT, 'Sources/RecordApp/**/*.swift')].sort.each do |path|
  relative_path = Pathname.new(path).relative_path_from(Pathname.new(ROOT)).to_s
  file_ref = app_group.new_file(relative_path)
  app_target.add_file_references([file_ref])
end

Dir[File.join(ROOT, 'Tests/**/*.swift')].sort.each do |path|
  relative_path = Pathname.new(path).relative_path_from(Pathname.new(ROOT)).to_s
  file_ref = tests_group.new_file(relative_path)
  test_target.add_file_references([file_ref])
end

[
  [core_target, "#{PRODUCT_BUNDLE_IDENTIFIER}.core"],
  [app_target, PRODUCT_BUNDLE_IDENTIFIER],
  [test_target, "#{PRODUCT_BUNDLE_IDENTIFIER}.tests"]
].each do |target, bundle_id|
  target.build_configurations.each do |config|
    config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = bundle_id
    config.build_settings['SWIFT_VERSION'] = '6.0'
    config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '14.0'
    config.build_settings['SDKROOT'] = 'macosx'
    config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
    config.build_settings['INFOPLIST_KEY_NSCameraUsageDescription'] = 'Record needs camera access to preview and record video.'
    config.build_settings['INFOPLIST_KEY_NSMicrophoneUsageDescription'] = 'Record needs microphone access to capture audio.'
    config.build_settings['ASSETCATALOG_COMPILER_APPICON_NAME'] = ''
    config.build_settings['ENABLE_HARDENED_RUNTIME'] = 'NO'
  end
end

framework_ref = project.products_group.files.find { |file| file.path == "#{CORE_TARGET_NAME}.framework" }
app_target.frameworks_build_phase.add_file_reference(framework_ref, true) if framework_ref
test_target.frameworks_build_phase.add_file_reference(framework_ref, true) if framework_ref

if framework_ref
  embed_phase = app_target.copy_files_build_phases.find { |phase| phase.name == 'Embed Frameworks' } ||
    app_target.new_copy_files_build_phase('Embed Frameworks')
  embed_phase.symbol_dst_subfolder_spec = :frameworks
  build_file = embed_phase.add_file_reference(framework_ref, true)
  build_file.settings = { 'ATTRIBUTES' => ['CodeSignOnCopy', 'RemoveHeadersOnCopy'] }
end

app_target.build_configurations.each do |config|
  config.build_settings['PRODUCT_NAME'] = 'Record'
  config.build_settings['SWIFT_EMIT_LOC_STRINGS'] = 'YES'
  config.build_settings['CODE_SIGN_STYLE'] = config.name == 'Debug' ? 'Manual' : 'Automatic'
  config.build_settings['CODE_SIGN_IDENTITY[sdk=macosx*]'] = config.name == 'Debug' ? '-' : ''
  config.build_settings['CODE_SIGNING_ALLOWED'] = 'YES'
  config.build_settings['DEVELOPMENT_TEAM'] = ''
  config.build_settings['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/../Frameworks']
  config.build_settings['PRODUCT_MODULE_NAME'] = 'Record'
  config.build_settings['ENABLE_PREVIEWS'] = 'YES'
end

core_target.build_configurations.each do |config|
  config.build_settings['PRODUCT_NAME'] = CORE_TARGET_NAME
  config.build_settings['PRODUCT_MODULE_NAME'] = CORE_TARGET_NAME
  config.build_settings['SKIP_INSTALL'] = 'YES'
  config.build_settings['DEFINES_MODULE'] = 'YES'
  config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
end

test_target.build_configurations.each do |config|
  config.build_settings['PRODUCT_NAME'] = TEST_TARGET_NAME
  config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
end

project.recreate_user_schemes
project.save

shared_scheme_dir = File.join(PROJECT_PATH, 'xcshareddata', 'xcschemes')
FileUtils.mkdir_p(shared_scheme_dir)
Dir[File.join(PROJECT_PATH, 'xcuserdata', '*', 'xcschemes', '*.xcscheme')].each do |scheme_path|
  FileUtils.cp(scheme_path, File.join(shared_scheme_dir, File.basename(scheme_path)))
end
FileUtils.rm_rf(File.join(PROJECT_PATH, 'xcuserdata'))

puts "Generated #{PROJECT_PATH}"
