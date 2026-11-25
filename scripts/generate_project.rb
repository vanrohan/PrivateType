require 'xcodeproj'

root = File.expand_path('..', __dir__)
project = Xcodeproj::Project.new(File.join(root, 'SimpleKeyboard.xcodeproj'))
project.build_configurations.each do |config|
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '18.0'
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['ARCHS'] = 'arm64'
end

app = project.new_target(:application, 'SimpleKeyboard', :ios, '18.0')
keyboard = project.new_target(:app_extension, 'SimpleKeyboardExtension', :ios, '18.0')
unit_tests = project.new_target(:unit_test_bundle, 'KeyboardCoreTests', :ios, '18.0')
ui_tests = project.new_target(:ui_test_bundle, 'SimpleKeyboardUITests', :ios, '18.0')
device_tests = project.new_target(:ui_test_bundle, 'SimpleKeysDeviceUITests', :ios, '18.0')

sources = Dir.glob(File.join(root, '{Core,Keyboard,Neural}', '*.swift')).sort
references = {}
def file_ref(project, root, path, references)
  relative = path.delete_prefix(root + '/')
  references[relative] ||= project.main_group.new_file(relative)
end
sources.each do |path|
  ref = file_ref(project, root, path, references)
  app.source_build_phase.add_file_reference(ref)
  keyboard.source_build_phase.add_file_reference(ref)
end
Dir.glob(File.join(root, 'App', '*.swift')).each do |path|
  app.source_build_phase.add_file_reference(file_ref(project, root, path, references))
end
Dir.glob(File.join(root, '{Tests/Core,Tests/iOS}', '*.swift')).each do |path|
  unit_tests.source_build_phase.add_file_reference(file_ref(project, root, path, references))
end
Dir.glob(File.join(root, 'Tests/UI', '*.swift')).each do |path|
  ui_tests.source_build_phase.add_file_reference(file_ref(project, root, path, references))
end
Dir.glob(File.join(root, 'Tests/DeviceUI', '*.swift')).each do |path|
  device_tests.source_build_phase.add_file_reference(file_ref(project, root, path, references))
end
privacy = file_ref(project, root, File.join(root, 'App/PrivacyInfo.xcprivacy'), references)
[app, keyboard].each { |target| target.resources_build_phase.add_file_reference(privacy) }
assets = file_ref(project, root, File.join(root, 'App/Assets.xcassets'), references)
app.resources_build_phase.add_file_reference(assets)
%w[LICENSE docs/Unicode-License.txt App/RuntimeLicenses.txt].each do |path|
  app.resources_build_phase.add_file_reference(file_ref(project, root, File.join(root, path), references))
end
{ app => 'App/Settings.bundle', keyboard => 'Keyboard/Settings.bundle' }.each do |target, path|
  ref = file_ref(project, root, File.join(root, path), references)
  ref.last_known_file_type = 'wrapper.plug-in'
  target.resources_build_phase.add_file_reference(ref)
end

model_targets = [app, keyboard, unit_tests]
dictionary = file_ref(project, root, File.join(root, 'Dictionaries'), references)
dictionary.last_known_file_type = 'folder'
model_targets.each { |target| target.resources_build_phase.add_file_reference(dictionary) }
Dir.glob(File.join(root, 'Models', '*')).sort.each do |path|
  next unless path.end_with?('.pte', '.txt', '.json', '.mlpackage', '.md')
  ref = file_ref(project, root, path, references)
  ref.last_known_file_type = 'folder.mlpackage' if path.end_with?('.mlpackage')
  targets = File.basename(path).start_with?('German') ? [unit_tests] : model_targets
  targets.each { |target| target.resources_build_phase.add_file_reference(ref) }
end
Dir.glob(File.join(root, 'Vendor/ExecuTorch', '*.xcframework')).sort.each do |path|
  ref = file_ref(project, root, path, references)
  [app, keyboard].each { |target| target.frameworks_build_phase.add_file_reference(ref) }
end
[app, keyboard].each do |target|
  target.build_configurations.each do |config|
    config.build_settings['OTHER_LDFLAGS'] = ['$(inherited)', '-all_load', '-lc++', '-framework', 'Accelerate']
  end
end

app.add_dependency(keyboard)
embed = app.new_copy_files_build_phase('Embed App Extensions')
embed.dst_subfolder_spec = '13'
embed.add_file_reference(keyboard.product_reference).settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
ui_tests.add_dependency(app)
device_tests.add_dependency(app)
unit_tests.add_dependency(app)
unit_tests.build_configurations.each do |config|
  config.build_settings['TEST_HOST'] = '$(BUILT_PRODUCTS_DIR)/SimpleKeyboard.app/SimpleKeyboard'
  config.build_settings['BUNDLE_LOADER'] = '$(TEST_HOST)'
  config.build_settings['SWIFT_INCLUDE_PATHS'] = ['$(inherited)', '$(BUILT_PRODUCTS_DIR)/include']
  config.build_settings['HEADER_SEARCH_PATHS'] = ['$(inherited)', '$(BUILT_PRODUCTS_DIR)/include']
end
app.build_configurations.each { |config| config.build_settings['ENABLE_TESTABILITY'] = 'YES' }

targets = {
  app => ['com.sonnesolutions.simplekeyboard', 'App/Info.plist'],
  keyboard => ['com.sonnesolutions.simplekeyboard.keyboard', 'Keyboard/Info.plist'],
  unit_tests => ['com.sonnesolutions.simplekeyboard.coretests', nil],
  ui_tests => ['com.sonnesolutions.simplekeyboard.uitests', nil],
  device_tests => ['com.sonnesolutions.simplekeyboard.deviceuitests', nil]
}
targets.each do |target, (bundle_id, plist)|
  target.build_configurations.each do |config|
    settings = config.build_settings
    settings['PRODUCT_BUNDLE_IDENTIFIER'] = bundle_id
    settings['SWIFT_VERSION'] = '5.0'
    settings['TARGETED_DEVICE_FAMILY'] = '1,2'
    settings['CODE_SIGN_STYLE'] = 'Automatic'
    settings['SWIFT_EMIT_LOC_STRINGS'] = 'YES'
    if plist
      settings['INFOPLIST_FILE'] = plist
    else
      settings['GENERATE_INFOPLIST_FILE'] = 'YES'
    end
  end
end
ui_tests.build_configurations.each { |config| config.build_settings['TEST_TARGET_NAME'] = app.name }
device_tests.build_configurations.each { |config| config.build_settings['TEST_TARGET_NAME'] = app.name }
keyboard.build_configurations.each { |config| config.build_settings['APPLICATION_EXTENSION_API_ONLY'] = 'YES' }

scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.add_test_target(unit_tests)
scheme.add_test_target(ui_tests)
scheme.set_launch_target(app)
scheme.save_as(project.path, 'SimpleKeyboard', true)
device_scheme = Xcodeproj::XCScheme.new
device_scheme.add_build_target(app)
device_scheme.add_test_target(device_tests)
device_scheme.set_launch_target(app)
device_scheme.save_as(project.path, 'SimpleKeys Device Checks', true)
project.save
puts 'Created SimpleKeyboard.xcodeproj'
