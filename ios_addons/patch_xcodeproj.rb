#!/usr/bin/env ruby
# encoding: utf-8
#
# Adds a File Provider Extension target to Runner.xcodeproj.
# Uses xcodeproj gem (bundled with CocoaPods on macOS runners).
#
# NOTE: This file is intentionally ASCII-only (no Japanese comments)
# to avoid a Ruby 3.3+ Prism parser bug where multi-byte comments
# combined with string interpolation trigger false syntax errors.

require 'xcodeproj'

PROJECT_PATH   = 'ios/Runner.xcodeproj'
EXTENSION_NAME = 'MusicPlayerFileProvider'
EXTENSION_DIR  = EXTENSION_NAME
MAIN_BUNDLE_ID = 'com.example.music_player'
EXT_BUNDLE_ID  = MAIN_BUNDLE_ID + '.FileProvider'
DEPLOYMENT_TGT = '16.0'

puts 'Opening ' + PROJECT_PATH + ' ...'
project = Xcodeproj::Project.open(PROJECT_PATH)

# --- Idempotency: remove existing extension target if present ---
existing = project.targets.find { |t| t.name == EXTENSION_NAME }
if existing
  puts 'Removing existing target: ' + EXTENSION_NAME
  project.targets.delete(existing)
end
existing_group = project.main_group.children.find { |c| c.display_name == EXTENSION_NAME }
existing_group.remove_from_project if existing_group

# --- 1. Create the extension target ---
puts 'Creating target: ' + EXTENSION_NAME
extension_target = project.new_target(
  :app_extension,
  EXTENSION_NAME,
  :ios,
  DEPLOYMENT_TGT,
  project.products_group,
  :swift
)

# --- 2. Configure build settings ---
extension_target.build_configurations.each do |config|
  bs = config.build_settings
  bs['PRODUCT_BUNDLE_IDENTIFIER']    = EXT_BUNDLE_ID
  bs['INFOPLIST_FILE']               = EXTENSION_DIR + '/Info.plist'
  bs['IPHONEOS_DEPLOYMENT_TARGET']   = DEPLOYMENT_TGT
  bs['SWIFT_VERSION']                = '5.0'
  bs['TARGETED_DEVICE_FAMILY']       = '1,2'
  bs['CODE_SIGN_STYLE']              = 'Manual'
  bs['CODE_SIGNING_ALLOWED']         = 'NO'
  bs['CODE_SIGN_IDENTITY']           = ''
  bs['CODE_SIGNING_REQUIRED']        = 'NO'
  bs['DEVELOPMENT_TEAM']             = ''
  bs['SKIP_INSTALL']                 = 'YES'
  bs['LD_RUNPATH_SEARCH_PATHS']      = '$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks'
end

# --- 3. Register source files ---
puts 'Adding source files ...'
group = project.main_group.new_group(EXTENSION_NAME, EXTENSION_DIR)

%w[FileProviderExtension.swift FileProviderItem.swift FileProviderEnumerator.swift].each do |name|
  file_ref = group.new_file(name)
  extension_target.source_build_phase.add_file_reference(file_ref)
  puts '  + ' + name
end

# Info.plist is referenced via INFOPLIST_FILE, not added to any build phase
group.new_file('Info.plist')
puts '  + Info.plist (reference only)'

# --- 4. Bump Runner target deployment target ---
runner_target = project.targets.find { |t| t.name == 'Runner' }
raise 'Runner target not found' if runner_target.nil?

runner_target.build_configurations.each do |config|
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = DEPLOYMENT_TGT
end
puts 'Bumped Runner deployment target to ' + DEPLOYMENT_TGT

# --- 5. Add Embed App Extensions build phase to Runner ---
runner_target.build_phases.dup.each do |phase|
  if phase.is_a?(Xcodeproj::Project::Object::PBXCopyFilesBuildPhase) && phase.name == 'Embed App Extensions'
    puts 'Removing existing Embed App Extensions phase'
    runner_target.build_phases.delete(phase)
  end
end

puts 'Adding Embed App Extensions phase to Runner'
embed_phase = runner_target.new_copy_files_build_phase('Embed App Extensions')
embed_phase.dst_subfolder_spec = '13'  # 13 = PlugIns folder
embed_phase.dst_path = ''
build_file = embed_phase.add_file_reference(extension_target.product_reference)
build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

runner_target.add_dependency(extension_target)
puts 'Added Runner -> ' + EXTENSION_NAME + ' dependency'

# --- Save ---
project.save
puts 'Project saved successfully.'
puts ''
puts '=== Final targets ==='
project.targets.each do |t|
  name = t.name
  ptype = t.product_type.to_s
  puts '  - ' + name + ' [' + ptype + ']'
end
