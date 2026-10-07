require 'json'
require 'minitest/autorun'
require 'open3'
require 'tmpdir'
require 'uri'
require_relative '../breez_passkey_patch'

class BreezPasskeyPatchTest < Minitest::Test
  Ref = Struct.new(:path, :source_tree)
  Phase = Struct.new(:files_references)
  Target = Struct.new(:name, :source_build_phase)
  Project = Struct.new(:path, :targets)
  Sandbox = Struct.new(:root)
  Installer = Struct.new(:pods_project, :sandbox)

  def setup
    package_config = File.expand_path('../../.dart_tool/package_config.json', __dir__)
    package = JSON.parse(File.read(package_config)).fetch('packages')
                  .find { |entry| entry['name'] == 'breez_sdk_spark_flutter' }
    @sdk = URI.join("file://#{package_config}", package.fetch('rootUri')).path
    @source = BreezPasskeyPatch::HASHES.keys.to_h do |name|
      [name, File.binread(File.join(@sdk, 'ios/Classes', name))]
    end
    @directory = Dir.mktmpdir('kute-breez-passkey-test')
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def patched(name)
    BreezPasskeyPatch.transform(name, @source.fetch(name))
  end

  def test_unknown_sdk_source_fails_instead_of_building_without_protection
    @source.each do |name, source|
      assert_raises(RuntimeError) { BreezPasskeyPatch.transform(name, source + "\n// changed upstream") }
    end
  end

  def test_previously_normalized_cocoapods_import_produces_identical_output
    name = 'PasskeyAssertionCore.swift'
    normalized = @source.fetch(name).sub(/^import PasskeyPRFHelperObjC\r?\n/, '')
    assert_equal patched(name), BreezPasskeyPatch.transform(name, normalized)
  end

  def test_assertion_and_registration_require_verification_and_throw_on_rng_failure
    core = patched('PasskeyAssertionCore.swift')
    assert_equal 2, core.scan('request.userVerificationPreference = .required').length
    assert_includes core, 'challenge: try Self.randomBytes(count: 32)'
    assert_includes core, 'let challenge = try Self.randomBytes(count: 32)'
    assert_includes core, 'let resolvedUserId = try Self.randomBytes(count: 16)'
    assert_includes core, 'let request = try makeAssertionRequest('
    refute_includes core, '_ = SecRandomCopyBytes'
  end

  def test_unsupported_ios_cannot_enter_creation_or_derivation
    plugin = patched('BreezSdkSparkPasskeyPlugin.swift')
    assert_equal 2, plugin.scan('#available(iOS 18.4, *)').length
    guard_position = plugin.index('if call.method == "createPasskey" || call.method == "deriveSeeds"')
    assert_operator guard_position, :<, plugin.index('switch call.method')
    assert_includes plugin[guard_position...plugin.index('switch call.method')], 'return'
  end

  def installer
    @installer ||= begin
      source_dir = File.join(@directory, '.symlinks/plugins/breez_sdk_spark_flutter/ios/Classes')
      FileUtils.mkdir_p(source_dir)
      @source.each { |name, contents| File.binwrite(File.join(source_dir, name), contents) }
      refs = @source.keys.map { |name| Ref.new(File.join(source_dir, name), '<absolute>') }
      target = Target.new('breez_sdk_spark_flutter', Phase.new(refs))
      project = Project.new(Pathname.new(File.join(@directory, 'Pods/Pods.xcodeproj')), [target])
      Installer.new(project, Sandbox.new(project.path.dirname))
    end
  end

  def test_generated_copies_are_compiled_and_original_sources_are_untouched
    refs = installer.pods_project.targets.first.source_build_phase.files_references
    originals = refs.to_h { |ref| [ref.path, File.binread(ref.path)] }
    2.times { BreezPasskeyPatch.install!(installer, ios_dir: @directory) }
    originals.each { |path, contents| assert_equal contents, File.binread(path) }
    refs.each do |ref|
      assert_equal 'SOURCE_ROOT', ref.source_tree
      assert_match(%r{\AKutePasskey/[^/]+\.swift\z}, ref.path)
      assert_equal patched(File.basename(ref.path)), File.binread(installer.sandbox.root.join(ref.path))
    end
  end

  def test_missing_compile_reference_blocks_the_build_before_any_files_are_written
    installer.pods_project.targets.first.source_build_phase.files_references.pop
    assert_raises(RuntimeError) { BreezPasskeyPatch.install!(installer, ios_dir: @directory) }
    refute File.exist?(File.join(@directory, 'Pods/KutePasskey'))
  end

  def test_missing_target_blocks_the_build
    installer.pods_project.targets.clear
    assert_raises(RuntimeError) { BreezPasskeyPatch.install!(installer, ios_dir: @directory) }
  end

  def test_patched_swift_parses_and_rng_failure_never_returns_partial_bytes
    skip 'Swift and Security.framework require macOS' unless RUBY_PLATFORM.include?('darwin')

    paths = @source.keys.map do |name|
      path = File.join(@directory, name)
      File.write(path, patched(name))
      path
    end
    output, status = Open3.capture2e('xcrun', 'swiftc', '-frontend', '-parse', *paths)
    assert status.success?, output

    random_function = patched('PasskeyAssertionCore.swift')[/    public static func randomBytes\(.*?^    \}/m]
    refute_nil random_function
    harness = <<~SWIFT
      import Foundation
      import Security
      enum PasskeyAssertionError: Error { case generic(String) }
      enum Harness {
      #{random_function}
      }
      do {
          _ = try Harness.randomBytes(count: 32) { count, buffer in
              buffer.initializeMemory(as: UInt8.self, repeating: 0x42, count: count / 2)
              return errSecNotAvailable
          }
          fatalError("Failed randomness returned partial bytes")
      } catch PasskeyAssertionError.generic(_) { }
      let bytes = try Harness.randomBytes(count: 32) { count, buffer in
          buffer.initializeMemory(as: UInt8.self, repeating: 0x42, count: count)
          return errSecSuccess
      }
      precondition(bytes == Data(repeating: 0x42, count: 32))
    SWIFT
    path = File.join(@directory, 'RandomTest.swift')
    File.write(path, harness)
    output, status = Open3.capture2e('xcrun', 'swift', '-module-cache-path',
      File.join(@directory, 'modules'), path)
    assert status.success?, output
  end
end
