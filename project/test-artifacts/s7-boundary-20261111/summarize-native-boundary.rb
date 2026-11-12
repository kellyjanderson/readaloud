require 'json'
require 'digest'
require 'uri'
input, output=ARGV
abort 'Usage: RECEIPT NEW_OUTPUT' unless input&&output&&!File.exist?(output)
abort 'Receipt exceeds32MiB diagnosis bound' unless File.size(input)<=32*1024*1024
receipt=JSON.parse(File.read(input))
audit=receipt.fetch('nativeQueueBoundaryAudit')
abort 'Wrong native audit schema' unless audit['schema']=='readaloud-native-queue-boundary-audit-v1'&&audit['enabled']==true
result={diagnosticOnly:true,passed:false,receipt:File.expand_path(input),receiptSha256:Digest::SHA256.file(input).hexdigest,limits:'Native snapshots are sequential, not atomic. Entry equality does not prove physical current at later seek execution. No acoustic/causal/acceptance inference.',players:[]}
audit.fetch('players').each do |player|
 sources=player.fetch('sources').to_h{|s|[s.fetch('sourceIdentity'),s]}
 items=player.fetch('items').to_h{|s|[s.fetch('itemIdentity'),s]}
 label=lambda do |item|
  source=sources[items.dig(item,'sourceIdentity')]
  source&&source['sourceURL'] ? URI::DEFAULT_PARSER.unescape(source['sourceURL']).split('/').last : nil
 end
 events=player.fetch('events')
 selected=events.select{|e|e['boundary'].include?('completion')||e['boundary'].include?('stall')||e['boundary'].include?('remove')}
 result[:players]<<{id:player['id'],sessionIdentity:player['sessionIdentity'],skipLoopOffRewind:player['skipLoopOffRewind'],overflow:player['overflow'],offMainSkipped:player['offMainSkipped'],identityRegistryOverflow:player['identityRegistryOverflow'],eventCount:events.length,trackedSources:sources.values.map{|s|s.slice('sourceIdentity','sourceURL','firstRevision')},boundaryCounts:events.group_by{|e|e['boundary']}.transform_values(&:length),rewindEntries:events.select{|e|e['boundary']=='completion.rewind.entry'}.map{|e|{unixMicros:e['unixMicros'],item:label.call(e['itemIdentity']),current:label.call(e['currentItemIdentity']),observedSameItemAtEntry:e['itemIdentity']==e['currentItemIdentity'],itemTimeSeconds:e.dig('itemState','currentTimeSeconds'),currentTimeSeconds:e.dig('currentItemState','currentTimeSeconds'),queueHead:label.call(e['queueSnapshotHeadIdentity']),details:e['details']}},selectedEvents:selected.map{|e|{boundary:e['boundary'],unixMicros:e['unixMicros'],item:label.call(e['itemIdentity']),current:label.call(e['currentItemIdentity']),logicalIndex:e['logicalIndex'],itemTimeSeconds:e.dig('itemState','currentTimeSeconds'),currentTimeSeconds:e.dig('currentItemState','currentTimeSeconds'),timeControlStatus:e['timeControlStatus'],reasonForWaiting:e['reasonForWaitingToPlay'],details:e['details']}}}
end
File.write(output,JSON.pretty_generate(result)+"\n")
puts JSON.generate(result[:players].map{|p|p.slice(:eventCount,:overflow,:offMainSkipped,:skipLoopOffRewind,:rewindEntries)})
