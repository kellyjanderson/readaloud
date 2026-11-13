# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative 'release_notices'

class ReleaseNoticesTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir('readaloud-notices-')
    FileUtils.mkdir_p(File.join(@root, 'macos'))
    FileUtils.mkdir_p(File.join(@root, 'third_party'))
    %w[pubspec.lock macos/Podfile.lock assets third_party/licenses].each do |path|
      FileUtils.cp_r(File.join(ReleaseNotices::ROOT, path), File.join(@root, path))
    end
    %w[flutter_onnxruntime just_audio].each do |package|
      directory = File.join(@root, 'third_party', package)
      FileUtils.mkdir_p(directory)
      FileUtils.cp(File.join(ReleaseNotices::ROOT, 'third_party', package, 'LICENSE'), directory)
    end
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def rewrite_inventory
    path = File.join(@root, 'third_party/licenses/inventory.json')
    inventory = JSON.parse(File.read(path))
    yield inventory
    File.write(path, JSON.generate(inventory))
  end

  def test_reviewed_snapshot_and_aggregate_match
    inventory = ReleaseNotices.validate(@root)
    assert_equal File.read(File.join(@root, 'third_party/licenses/NOTICES.txt')), ReleaseNotices.text(inventory, @root)
    assert inventory.fetch('blockers').any? { |blocker| blocker['id'] == 'project-grant' }
  end

  def test_lockfile_drift_fails
    File.write(File.join(@root, 'pubspec.lock'), "# changed\n", mode: 'a')
    assert_match(/Lockfile changed/, assert_raises(RuntimeError) { ReleaseNotices.validate(@root) }.message)
  end

  def test_missing_dependency_fails_even_when_text_exists
    rewrite_inventory { |inventory| inventory['packages'].reject! { |item| item['id'] == 'dart:just_audio' } }
    assert_match(/dependency inventory differs/, assert_raises(RuntimeError) { ReleaseNotices.validate(@root) }.message)
  end

  def test_path_override_identity_fails_even_when_lock_hash_is_updated
    path = File.join(@root, 'pubspec.lock')
    lock = YAML.load_file(path)
    lock.fetch('packages').fetch('just_audio').fetch('description')['path'] = 'third_party/unreviewed_audio'
    File.write(path, YAML.dump(lock))
    rewrite_inventory { |inventory| inventory['lockfiles']['pubspec.lock'] = Digest::SHA256.file(path).hexdigest }
    assert_match(/Dependency path changed/, assert_raises(RuntimeError) { ReleaseNotices.validate(@root) }.message)
  end

  def test_vendored_grant_drift_fails_even_when_collected_text_is_unchanged
    File.write(File.join(@root, 'third_party/just_audio/LICENSE'), 'changed vendored grant')
    assert_match(/Vendored notice changed/, assert_raises(RuntimeError) { ReleaseNotices.validate(@root) }.message)
  end

  def test_changed_grant_and_asset_fail
    File.write(File.join(@root, 'third_party/licenses/dart/just_audio/LICENSE'), 'truncated grant')
    assert_match(/Notice changed/, assert_raises(RuntimeError) { ReleaseNotices.validate(@root) }.message)
    FileUtils.cp(File.join(ReleaseNotices::ROOT, 'third_party/licenses/dart/just_audio/LICENSE'), File.join(@root, 'third_party/licenses/dart/just_audio/LICENSE'))
    asset = File.join(@root, 'assets/lexicon.json')
    # Source assets may be read-only; this test mutates only its private copy.
    File.chmod(0o600, asset)
    File.write(asset, '{}')
    assert_match(/Asset changed/, assert_raises(RuntimeError) { ReleaseNotices.validate(@root) }.message)
  end

  def test_unrecorded_asset_and_path_escape_fail
    File.write(File.join(@root, 'assets/unreviewed.txt'), 'new asset')
    assert_match(/asset set changed/, assert_raises(RuntimeError) { ReleaseNotices.validate(@root) }.message)
    File.delete(File.join(@root, 'assets/unreviewed.txt'))
    rewrite_inventory { |inventory| inventory['packages'].first['notice'] = '../outside-LICENSE' }
    assert_match(/Unsafe notice path/, assert_raises(RuntimeError) { ReleaseNotices.validate(@root) }.message)
  end
end
