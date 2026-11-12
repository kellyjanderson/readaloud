require 'fileutils'
root='/Users/k/.codex/worktrees/model-lifecycle-s7/readaloud'
framework="#{root}/.readaloud-tools/flutter-3.41.5-arm64/bin/cache/artifacts/engine/darwin-x64-release/FlutterMacOS.xcframework/macos-arm64_x86_64"
out=File.expand_path('tmp/s7-final/native-controls')
abort 'output exists' if File.exist?(out)
FileUtils.mkdir_p(out)
old="#{out}/old";FileUtils.mkdir_p(old)
IO.popen(['git','archive','6a9061c','third_party/just_audio'],'rb'){|archive|IO.popen(['tar','-x','-C',old],'wb'){|tar|IO.copy_stream(archive,tar)}}
mutant="#{out}/mutant";FileUtils.cp_r('third_party/just_audio',mutant)
p="#{mutant}/darwin/just_audio/Sources/just_audio/AudioPlayer.m";s=File.read(p);before='} else if (_processingState != psCompleted) {';abort 'anchor missing' unless s.include?(before);File.write(p,s.sub(before,'} else if (endedPlayerItem != head) {'))
[['old-source',"#{old}/third_party/just_audio"],['same-head-mutant',mutant]].each do|name,dir|
 log="#{out}/#{name}.log"
 ok=system({'JUST_AUDIO_SOURCE_DIR'=>dir,'FLUTTER_FRAMEWORK_DIR'=>framework,'READALOUD_FINAL_EOF_SCENARIO'=>'same-head-early-final'},'bash','third_party/just_audio/test/local_native/run.sh',out:log,err:[:child,:out])
 status=$?.exitstatus;output=File.read(log);puts "#{name}: exit=#{status}"
 abort 'wrong negative failure' if ok || !output.include?('single same-head early final witness lost at Pause EOF')
end
ok=system({'FLUTTER_FRAMEWORK_DIR'=>framework},'bash','third_party/just_audio/test/local_native/run.sh',out:"#{out}/fixed-full.log",err:[:child,:out]);abort 'fixed failed' unless ok
puts 'PASS fixed and meaningful negative controls'
