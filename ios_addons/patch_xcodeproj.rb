#!/usr/bin/env ruby
# ============================================================
# Runner.xcodeproj に File Provider Extension ターゲットを追加する。
# xcodeproj gem を使用（macOSランナーに標準で入っている）。
# ============================================================

require 'xcodeproj'

PROJECT_PATH   = 'ios/Runner.xcodeproj'
EXTENSION_NAME = 'MusicPlayerFileProvider'
EXTENSION_DIR  = EXTENSION_NAME
MAIN_BUNDLE_ID = 'com.example.music_player'
EXT_BUNDLE_ID  = "#{MAIN_BUNDLE_ID}.FileProvider"
DEPLOYMENT_TGT = '16.0'

puts "Opening #{PROJECT_PATH} ..."
project = Xcodeproj::Project.open(PROJECT_PATH)

# ============================================================
# 冪等性のため、既存の拡張機能ターゲット・グループがあれば削除
# ============================================================
existing = project.targets.find { |t| t.name == EXTENSION_NAME }
if existing
  puts "Removing existing target: #{EXTENSION_NAME}"
  project.targets.delete(existing)
end
existing_group = project.main_group.children.find { |c| c.display_name == EXTENSION_NAME }
existing_group.remove_from_project if existing_group

# ============================================================
# 1. 拡張機能ターゲット作成
# ============================================================
puts "Creating target: #{EXTENSION_NAME}"
extension_target = project.new_target(
  :app_extension,
  EXTENSION_NAME,
  :ios,
  DEPLOYMENT_TGT,
  project.products_group,
  :swift
)

# ============================================================
# 2. ビルド設定
# ============================================================
extension_target.build_configurations.each do |config|
  bs = config.build_settings
  bs['PRODUCT_BUNDLE_IDENTIFIER']    = EXT_BUNDLE_ID
  bs['INFOPLIST_FILE']               = "#{EXTENSION_DIR}/Info.plist"
  bs['IPHONEOS_DEPLOYMENT_TARGET']   = DEPLOYMENT_TGT
  bs['SWIFT_VERSION']                = '5.0'
  bs['TARGETED_DEVICE_FAMILY']       = '1,2'  # iPhone + iPad
  bs['CODE_SIGN_STYLE']              = 'Manual'
  bs['CODE_SIGNING_ALLOWED']         = 'NO'
  bs['CODE_SIGN_IDENTITY']           = ''
  bs['CODE_SIGNING_REQUIRED']        = 'NO'
  bs['DEVELOPMENT_TEAM']             = ''
  bs['SKIP_INSTALL']                 = 'YES'
  bs['LD_RUNPATH_SEARCH_PATHS']      = '$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks'
end

# ============================================================
# 3. ソースファイル登録
# ============================================================
puts "Adding source files ..."
group = project.main_group.new_group(EXTENSION_NAME, EXTENSION_DIR)

%w[FileProviderExtension.swift FileProviderItem.swift FileProviderEnumerator.swift].each do |name|
  file_ref = group.new_file(name)
  extension_target.source_build_phase.add_file_reference(file_ref)
  puts "  + #{name}"
end

# Info.plistはINFOPLIST_FILEで参照されるので、ビルドフェーズには追加しない
group.new_file('Info.plist')
puts "  + Info.plist (reference only)"

# ============================================================
# 4. Runner ターゲットのデプロイターゲット引き上げ
# ============================================================
runner_target = project.targets.find { |t| t.name == 'Runner' }
raise "Runner target not found!" if runner_target.nil?

runner_target.build_configurations.each do |config|
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = DEPLOYMENT_TGT
end
puts "Bumped Runner deployment target to #{DEPLOYMENT_TGT}"

# ============================================================
# 5. Runner に Embed App Extensions ビルドフェーズを追加
# ============================================================
# 冪等: 既存の Embed App Extensions フェーズを削除
runner_target.build_phases.dup.each do |phase|
  if phase.is_a?(Xcodeproj::Project::Object::PBXCopyFilesBuildPhase) && phase.name == 'Embed App Extensions'
    puts "Removing existing Embed App Extensions phase"
    runner_target.build_phases.delete(phase)
  end
end

puts "Adding Embed App Extensions phase to Runner"
embed_phase = runner_target.new_copy_files_build_phase('Embed App Extensions')
embed_phase.dst_subfolder_spec = '13'  # 13 = PlugIns folder
embed_phase.dst_path = ''
build_file = embed_phase.add_file_reference(extension_target.product_reference)
build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

runner_target.add_dependency(extension_target)
puts "Added Runner -> #{EXTENSION_NAME} dependency"

# ============================================================
# Save
# ============================================================
project.save
puts "Project saved successfully."
puts ""
puts "=== Targets ==="
project.targets.each { |t| puts "  - #{t.name} (#{t.product_typeR}Aroj