require 'digest'
require 'fileutils'
require 'pathname'

# Scoped to breez-sdk-spark-flutter v0.26.0, commit b64789f0904f634e440e0cd7038e0cc5998342d5
# (both sources unchanged since v0.23.0, 5943a3e7; re-reviewed on the bump).
# Sources are read-only: CocoaPods compiles generated copies inside Pods instead
# of modifying Flutter's shared package cache. An SDK change needs a new review.
module BreezPasskeyPatch
  HASHES = {
    'PasskeyAssertionCore.swift' => 'b80a649e524f48e8fda2e125c6686f72c063f08ad3a162d4f11d3baf49a79a52', # gitleaks:allow -- public SDK source SHA-256
    'BreezSdkSparkPasskeyPlugin.swift' => '7cb4d8acde28c65a4b3a25bd722b78b12d77bef1d888f8bb65de7727b06a9b21' # gitleaks:allow -- public SDK source SHA-256
  }.freeze

  def self.replace_once(source, before, after)
    raise "Breez passkey patch no longer matches: #{before.lines.first.strip}" unless source.scan(before).length == 1

    source.sub(before, after)
  end

  def self.transform(name, source)
    # Upstream's standalone ObjC module is already in the CocoaPods umbrella.
    # This also accepts a cache normalized by the previous build-only hook.
    source = source.sub(/^import PasskeyPRFHelperObjC\r?\n/, '')
    unless Digest::SHA256.hexdigest(source) == HASHES.fetch(name)
      raise "Unreviewed Breez passkey source #{name}; review the SDK before building"
    end

    if name == 'PasskeyAssertionCore.swift'
      source = replace_once(source,
        ') -> ASAuthorizationPlatformPublicKeyCredentialAssertionRequest {',
        ') throws -> ASAuthorizationPlatformPublicKeyCredentialAssertionRequest {')
      source = replace_once(source,
        'let request = makeAssertionRequest(', 'let request = try makeAssertionRequest(')
      source = replace_once(source,
        'let request = provider.createCredentialAssertionRequest(challenge: Self.randomBytes(count: 32))',
        "let request = provider.createCredentialAssertionRequest(challenge: try Self.randomBytes(count: 32))\n        request.userVerificationPreference = .required")
      source = replace_once(source,
        'let challenge = Self.randomBytes(count: 32)', 'let challenge = try Self.randomBytes(count: 32)')
      source = replace_once(source,
        'let resolvedUserId = Self.randomBytes(count: 16)', 'let resolvedUserId = try Self.randomBytes(count: 16)')
      source = replace_once(source,
        "            userID: resolvedUserId\n        )",
        "            userID: resolvedUserId\n        )\n        request.userVerificationPreference = .required")
      source = replace_once(source, <<~'BEFORE'.chomp, <<~'AFTER'.chomp)
        public static func randomBytes(count: Int) -> Data {
                var bytes = [UInt8](repeating: 0, count: count)
                _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
                return Data(bytes)
            }
      BEFORE
        public static func randomBytes(
                count: Int,
                generator: (Int, UnsafeMutableRawPointer) -> OSStatus = {
                    SecRandomCopyBytes(kSecRandomDefault, $0, $1)
                }
            ) throws -> Data {
                guard count > 0 else {
                    throw PasskeyAssertionError.generic("Invalid random byte count")
                }
                var bytes = Data(count: count)
                let status = bytes.withUnsafeMutableBytes { buffer in
                    generator(buffer.count, buffer.baseAddress!)
                }
                guard status == errSecSuccess else {
                    throw PasskeyAssertionError.generic("Secure random generation failed")
                }
                return bytes
            }
      AFTER
    else
      source = replace_once(source, 'if #available(iOS 18.0, *) {', 'if #available(iOS 18.4, *) {')
      source = replace_once(source,
        'public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {',
        <<~'SWIFT'.chomp)
          public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
                  if call.method == "createPasskey" || call.method == "deriveSeeds" {
                      guard #available(iOS 18.4, *) else {
                          result(FlutterError(code: "ERR_PRF_NOT_SUPPORTED",
                              message: "Passkey PRF requires iOS 18.4 or newer", details: nil))
                          return
                      }
                  }
        SWIFT
    end
    source
  end

  def self.install!(installer, ios_dir:)
    targets = installer.pods_project.targets.select { |target| target.name == 'breez_sdk_spark_flutter' }
    raise 'Expected exactly one Breez SDK CocoaPods target' unless targets.length == 1

    source_dir = File.join(ios_dir, '.symlinks/plugins/breez_sdk_spark_flutter/ios/Classes')
    output_dir = installer.sandbox.root.join('KutePasskey')
    replacements = HASHES.keys.map do |name|
      refs = targets.first.source_build_phase.files_references.select { |ref| File.basename(ref.path) == name }
      raise "Expected exactly one Breez compile reference for #{name}" unless refs.length == 1

      [refs.first, name, transform(name, File.binread(File.join(source_dir, name)))]
    end
    FileUtils.mkdir_p(output_dir)
    replacements.each do |ref, name, source|
      destination = output_dir.join(name)
      File.binwrite(destination, source)
      ref.source_tree = 'SOURCE_ROOT'
      ref.path = destination.relative_path_from(installer.pods_project.path.dirname).to_s
    end
  end
end
