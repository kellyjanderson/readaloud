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
    File.write(File.join(@tree, 'bin/python'), "#!/bin/sh\necho fixture\n")
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
end
