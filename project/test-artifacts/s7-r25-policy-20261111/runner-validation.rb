require 'tmpdir'
require 'fileutils'
require 'json'
require 'open3'
require 'rbconfig'
Dir.mktmpdir('radoc-runner-validation-') do |root|
  helper = File.join(root, 'mock_native.rb')
  File.write(helper, <<~'MOCK')
    require 'json'
    require 'stringio'
    $qa_running = false
    MockStatus = Struct.new(:exitstatus) { def success?; exitstatus == 0; end }
    module Kernel
      def system(*args)
        raise 'Unexpected external command' unless args[1].end_with?('/verify_macos_release_entitlements.rb')
        true
      end
    end
    class << IO
      def popen(args, *rest)
        raise "Unexpected read command #{args.inspect}" unless args[0] == '/usr/bin/pgrep'
        yield StringIO.new($qa_running ? "101\n" : '')
      end
    end
    class << Process
      def spawn(*args)
        File.open(ENV.fetch('MOCK_CALLS'), 'a') { |f| f.puts JSON.generate(args) }
        case args[0]
        when '/usr/bin/open'
          $qa_running = true
          receipt = args[-2]
          now = Process.clock_gettime(Process::CLOCK_MONOTONIC_RAW, :nanosecond)
          File.write(receipt, JSON.generate({
            passed: true, timingClockDomain: 'CLOCK_MONOTONIC_RAW',
            appStartupCompleteMonotonicRawNanos: ENV['MOCK_BAD_TIMING'] ? 0 : now,
            documentLoadRequestedMonotonicRawNanos: now + 1,
            startupSynthesisCallbacks: 0, startupNativeSources: 0,
            controlledCaptureGate: false, resourceShutdownComplete: true,
            observedSourceEndWord: 100, originalSourceExpectedWordCount: 100,
            peakPcm16: 100, nativePlaybackPositions: {sampledSourcePositionTotalMs: 500}
          }))
          202
        when '/usr/bin/osascript'
          $qa_running = false
          404
        else
          raise "Unexpected process #{args.inspect}" unless args[0] == ENV.fetch('MOCK_CAPTURE')
          303
        end
      end
      def wait2(pid, *args); [pid, MockStatus.new(0)]; end
      def kill(signal, pid)
        raise Errno::ESRCH unless $qa_running && pid == 101 && signal == 0
        1
      end
    end
  MOCK
  bundle = File.join(root, 'QA.app')
  app = File.join(bundle, 'Contents/MacOS/read_aloud')
  capture = File.join(root, 'capture')
  FileUtils.mkdir_p(File.dirname(app))
  [app, capture].each { |path| File.write(path, 'not a real executable'); File.chmod(0700, path) }
  model = File.join(root, 'model')
  FileUtils.mkdir_p(model)
  book = File.join(root, 'book.txt')
  File.write(book, ('word ' * 100))
  base = {'RUBYOPT'=>"-r#{helper}", 'MOCK_CAPTURE'=>capture, 'READALOUD_MLX_TTS_MODEL_PATH'=>model,
    'READALOUD_MLX_PYTHON'=>nil, 'READALOUD_S7_INFERENCE_POLICY'=>nil,
    'READALOUD_FIRST_LOAD_MANAGED_MODEL'=>nil, 'MOCK_BAD_TIMING'=>nil}
  cases = [
    ['default', {}, true, nil],
    ['utility', {'READALOUD_S7_INFERENCE_POLICY'=>'utility'}, false, 'QA-only child scheduling'],
    ['background', {'READALOUD_S7_INFERENCE_POLICY'=>'background-utility'}, false, 'QA-only child scheduling'],
    ['invalid', {'READALOUD_S7_INFERENCE_POLICY'=>'high'}, false, 'Invalid QA inference policy'],
    ['missing', {'READALOUD_MLX_TTS_MODEL_PATH'=>nil}, false, 'Missing existing model'],
    ['managed', {'READALOUD_MLX_TTS_MODEL_PATH'=>nil, 'READALOUD_FIRST_LOAD_MANAGED_MODEL'=>'1'}, true, nil],
    ['conflict', {'READALOUD_FIRST_LOAD_MANAGED_MODEL'=>'1'}, false, 'Managed model mode cannot'],
    ['timing', {'MOCK_BAD_TIMING'=>'1'}, false, 'Missing post-startup native timing boundaries']
  ]
  cases.each do |name, changes, expected_success, expected_error|
    output = File.join(root, name)
    calls = File.join(root, "#{name}-calls.jsonl")
    stdout, stderr, status = Open3.capture3(base.merge(changes).merge('MOCK_CALLS'=>calls), RbConfig.ruby,
      File.expand_path('tools/run_radoc_first_load_smoke.rb'), bundle, 'fish_drama3', book, output, capture)
    raise "#{name}: wrong exit #{stdout} #{stderr}" unless status.success? == expected_success
    raise "#{name}: missing failure #{stderr}" if expected_error && !stderr.include?(expected_error)
    if File.file?(calls)
      invocation = JSON.parse(File.readlines(calls).first)
      expected_policy = changes['READALOUD_S7_INFERENCE_POLICY']
      if expected_policy
        raise "#{name}: missing policy forwarding" unless invocation.include?("READALOUD_S7_INFERENCE_POLICY=#{expected_policy}")
      else
        raise "#{name}: changed default policy" if invocation.any? { |x| x.is_a?(String) && x.start_with?('READALOUD_S7_INFERENCE_POLICY=') }
      end
      result = JSON.parse(File.read(File.join(output, 'runner.json')))
      raise "#{name}: cleanup not verified" unless result['normalQuit'] && result['appExitVerified'] && !result['forcedCleanup'] && result['remainingOwnedPids'].empty?
      raise "#{name}: wrong verdict" unless result['passed'] == expected_success
      if name == 'managed'
        raise 'Managed path not offline' unless invocation.include?('HF_HUB_OFFLINE=1')
        raise 'Managed path did not clear inherited override' unless invocation.include?('READALOUD_MLX_TTS_MODEL_PATH=')
      end
    end
    puts "PASS mocked runner #{name}"
  end
end
