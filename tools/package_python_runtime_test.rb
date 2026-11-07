# frozen_string_literal: true
require 'minitest/autorun'
require 'tmpdir'
require_relative 'package_python_runtime'

class PackagedPythonRuntimeTest < Minitest::Test
  def setup
    @temp = Dir.mktmpdir('readaloud-runtime-packaging-')
    @tree = File.join(@temp, 'standalone')
    @resources = File.join(@temp, 'Resources')
    @output = File.join(@resources, 'python-runtimes')
    FileUtils.mkdir_p(File.join(@tree, 'bin'))
    FileUtils.mkdir_p(File.join(@tree, 'include/python3.12'))
    File.write(File.join(@tree, 'include/python3.12/patchlevel.h'), '#define PY_VERSION "3.12.99"')
    c = File.join(@temp, 'fixture.c')
    File.write(c, 'int main(void) { return 0; }')
    PackagedPythonRuntime.capture('/usr/bin/clang', '-arch', 'arm64', c, '-o', File.join(@tree, 'bin/python'))
    PackagedPythonRuntime.capture('/usr/bin/codesign', '--force', '--sign', '-', File.join(@tree, 'bin/python'))
    File.chmod(0o755, File.join(@tree, 'bin/python'))
    File.symlink('python', File.join(@tree, 'bin/alias'))
    File.write(File.join(@tree, 'LICENSE'), 'retained license')
  end
  def teardown
    FileUtils.remove_entry(@temp)
  end
  def package(id = 'mlx')
    PackagedPythonRuntime.package(root: @tree, runtime_id: id, executable: 'bin/python', output: @output)
  end
  def test_manifest_includes_exact_tree_modes_links_packages_and_postsign_content_identity
    info = File.join(@tree, 'lib/python3.12/site-packages/example-1.2.dist-info')
    FileUtils.mkdir_p(info)
    File.write(File.join(info, 'METADATA'), "Name: example\nVersion: 1.2\n")
    value = package
    assert_equal 'Python 3.12.99', value['python']
    assert_equal [{ 'name' => 'example', 'version' => '1.2' }], value['packages']
    assert_equal 'python', value['entries'].find { |e| e['path'] == 'bin/alias' }['target']
    assert_equal 0o755, value['entries'].find { |e| e['path'] == 'bin/python' }['mode']
    first = value['signedTreeDigest']
    File.write(File.join(@tree, 'LICENSE'), 'new content, same source location')
    refute_equal first, package['signedTreeDigest']
  end
  def test_full_candidate_requires_both_archives_and_rejects_corruption_and_expanded_output
    package
    assert_raises(RuntimeError) { PackagedPythonRuntime.validate_resources(@resources) }
    package('modernbooknlp')
    assert_equal %w[mlx modernbooknlp], PackagedPythonRuntime.validate_resources(@resources).keys
    FileUtils.mkdir_p(File.join(@resources, 'mlx-python'))
    assert_raises(RuntimeError) { PackagedPythonRuntime.validate_resources(@resources) }
    FileUtils.rmdir(File.join(@resources, 'mlx-python'))
    File.write(File.join(@output, 'mlx.zip'), 'corrupt')
    assert_raises(RuntimeError) { PackagedPythonRuntime.validate_resources(@resources) }
  end
  def test_build_rejects_escaping_link_without_modifying_source
    File.symlink('../../outside', File.join(@tree, 'bin/escape'))
    assert_raises(Errno::ENOENT, RuntimeError) { package }
    assert File.symlink?(File.join(@tree, 'bin/escape'))
  end

  def test_native_content_classification_retains_extensionless_code_and_metal_in_bundle
    FileUtils.cp(File.join(@tree, 'bin/python'), File.join(@tree, 'bin/tool'))
    File.write(File.join(@tree, 'bin/kernels.metallib'), 'Metal resource fixture')
    value = package
    native = value['entries'].select { |entry| entry['type'] == 'bundledNative' }.map { |entry| entry['path'] }
    assert_equal %w[bin/kernels.metallib bin/python bin/tool], native
    assert File.file?(File.join(@output, 'mlx-native/bin/tool'))
    inventory = PackagedPythonRuntime.capture('/usr/bin/zipinfo', '-1', File.join(@output, 'mlx.zip')).lines.map(&:strip)
    refute_includes inventory, 'bin/tool'
    refute_includes inventory, 'bin/python'
    refute_includes inventory, 'bin/kernels.metallib'
    assert_includes inventory, 'LICENSE'
  end

  def test_known_native_suffix_cannot_disguise_non_macho
    File.write(File.join(@tree, 'bin/invalid.so'), 'not native code')
    assert_match(/Expected Mach-O/, assert_raises(RuntimeError) { package }.message)
  end

  def test_empty_package_markers_and_short_data_remain_archive_members
    File.write(File.join(@tree, '__init__.py'), '')
    File.binwrite(File.join(@tree, 'short-data'), "\x01\x02")
    value = package
    %w[__init__.py short-data].each do |name|
      assert_equal 'file', value['entries'].find { |entry| entry['path'] == name }['type']
      bytes = PackagedPythonRuntime.capture('/usr/bin/unzip', '-p', File.join(@output, 'mlx.zip'), name)
      assert_equal File.binread(File.join(@tree, name)), bytes
    end
  end

  def test_native_admission_accepts_single_arm64_fat_wrapper_and_refuses_additional_architectures
    arm = File.join(@tree, 'bin/python')
    fat = File.join(@tree, 'bin/fat-tool')
    PackagedPythonRuntime.capture('/usr/bin/lipo', '-create', arm, '-output', fat)
    PackagedPythonRuntime.capture('/usr/bin/codesign', '--force', '--sign', '-', fat)
    assert package['entries'].any? { |entry| entry['path'] == 'bin/fat-tool' && entry['type'] == 'bundledNative' }
    intel = File.join(@temp, 'intel')
    PackagedPythonRuntime.capture('/usr/bin/clang', '-arch', 'x86_64', File.join(@temp, 'fixture.c'), '-o', intel)
    File.unlink(fat)
    PackagedPythonRuntime.capture('/usr/bin/lipo', '-create', arm, intel, '-output', fat)
    PackagedPythonRuntime.capture('/usr/bin/codesign', '--force', '--sign', '-', fat)
    assert_match(/arm64-only/, assert_raises(RuntimeError) { package }.message)
  end

  def test_candidate_rejects_changed_native_code_and_undeclared_native_members
    package
    package('modernbooknlp')
    target = File.join(@output, 'mlx-native/bin/python')
    original = File.binread(target)
    File.binwrite(target, 'changed code')
    assert_raises(RuntimeError) { PackagedPythonRuntime.validate_resources(@resources) }
    File.binwrite(target, original)
    File.write(File.join(@output, 'mlx-native/undeclared'), 'extra')
    assert_raises(RuntimeError) { PackagedPythonRuntime.validate_resources(@resources) }
  end

  def test_only_bytecode_with_corresponding_source_is_omitted
    directory = File.join(@tree, 'lib/python3.12/example')
    cache = File.join(directory, '__pycache__')
    FileUtils.mkdir_p(cache)
    File.write(File.join(directory, 'module.py'), 'value = 1')
    %w[module.cpython-312.pyc module.cpython-312.opt-1.pyc sourceless.cpython-312.pyc].each do |name|
      File.write(File.join(cache, name), 'bytecode fixture')
    end
    original = package.fetch('entries').map { |entry| entry.fetch('path') }
    assert_includes original, 'lib/python3.12/example/__pycache__/module.cpython-312.pyc'
    PackagedPythonRuntime.omit_redundant_bytecode(@tree)
    names = package.fetch('entries').map { |entry| entry.fetch('path') }
    assert_includes names, 'lib/python3.12/example/module.py'
    assert_includes names, 'lib/python3.12/example/__pycache__/sourceless.cpython-312.pyc'
    refute names.any? { |name| name.end_with?('/module.cpython-312.pyc', '/module.cpython-312.opt-1.pyc') }
  end

  def test_bytecode_omission_refuses_escaping_cache_before_mutation
    outside = File.join(@temp, 'outside')
    FileUtils.mkdir_p(outside)
    cached = File.join(outside, 'module.cpython-312.pyc')
    File.write(cached, 'must remain untouched')
    File.write(File.join(@tree, 'module.py'), 'value = 1')
    File.symlink(outside, File.join(@tree, '__pycache__'))
    assert_raises(RuntimeError) { PackagedPythonRuntime.omit_redundant_bytecode(@tree) }
    assert_equal 'must remain untouched', File.read(cached)
  end
end
