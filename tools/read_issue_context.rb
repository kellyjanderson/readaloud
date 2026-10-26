#!/usr/bin/env ruby
# Read-only GitHub issue projection. No local cache or planning authority.
require 'json'
require 'open3'
require 'optparse'

module IssueContext
  START = '<!-- readaloud:current:start -->'
  FINISH = '<!-- readaloud:current:end -->'

  def self.current(body)
    raise 'Expected exactly one current block; reconcile the issue before dispatch.' unless body.scan(START).length == 1 && body.scan(FINISH).length == 1
    first = body.index(START) + START.length
    last = body.index(FINISH)
    raise 'Current block markers are reversed.' unless last > first
    result = body[first...last].strip
    raise 'Current block is empty.' if result.empty?
    result
  end

  def self.headings(body)
    fenced = false
    fence = nil
    body.lines.each_with_index.filter_map do |line, index|
      if line.match?(/^\s{0,3}(`{3,}|~{3,})/)
        mark = line.strip[0]
        if !fenced
          fenced = true
          fence = mark
        elsif mark == fence
          fenced = false
        end
        next
      end
      match = fenced ? nil : /\A(\#{1,6})\s+(.+?)\s*\n?\z/.match(line)
      [index, match[1].length, match[2].sub(/\s+#+\s*$/, '')] if match
    end
  end

  def self.section(body, title)
    all = headings(body)
    matches = all.select { |_, _, name| name == title }
    raise "Expected one heading named #{title.inspect}; use --headings." unless matches.length == 1
    first, level, = matches.first
    last = all.find { |index, depth, _| index > first && depth <= level }&.first || body.lines.length
    body.lines[first...last].join.strip
  end

  def self.api(path)
    out, err, status = Open3.capture3('gh', 'api', path)
    raise "GitHub read failed: #{err.strip}" unless status.success?
    JSON.parse(out)
  end

  def self.validate_comment(comment, repo, number)
    raise 'Comment belongs to a different issue' unless comment.fetch('issue_url').end_with?("/repos/#{repo}/issues/#{number}")
  end

  def self.run(args)
    repo = 'kellyjanderson/readaloud'
    mode = :current
    value = nil
    selected = false
    choose = lambda do |kind, argument = nil|
      raise OptionParser::InvalidArgument, 'Choose only one read mode' if selected
      mode, value, selected = kind, argument, true
    end
    parser = OptionParser.new do |o|
      o.banner = 'Usage: ruby tools/read_issue_context.rb NUMBER [--headings | --section TITLE | --comment ID | --full] [--repo OWNER/REPO]'
      o.on('--headings') { choose.call(:headings) }
      o.on('--section TITLE') { |v| choose.call(:section, v) }
      o.on('--comment ID') { |v| choose.call(:comment, v) }
      o.on('--full') { choose.call(:full) }
      o.on('--repo OWNER/REPO') { |v| repo = v }
      o.on('-h', '--help') { puts o; return }
    end
    parser.parse!(args)
    number = args.shift
    raise parser.to_s unless args.empty? && number&.match?(/\A[1-9]\d*\z/)
    raise 'Invalid repository' unless repo.match?(/\A[\w.-]+\/[\w.-]+\z/)
    if mode == :comment
      raise 'Comment ID must be numeric' unless value.match?(/\A[1-9]\d*\z/)
      comment = api("repos/#{repo}/issues/comments/#{value}")
      validate_comment(comment, repo, number)
      puts comment.fetch('html_url'), comment.fetch('body')
      return
    end
    issue = api("repos/#{repo}/issues/#{number}")
    body = issue.fetch('body').to_s
    output = case mode
             when :current then current(body)
             when :headings then headings(body).map { |_, depth, name| "#{'#' * depth} #{name}" }.join("\n")
             when :section then section(body, value)
             when :full then body
             end
    puts "##{number} #{issue.fetch('title')} — #{issue.fetch('html_url')}", output
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    IssueContext.run(ARGV)
  rescue StandardError => e
    warn e.message
    exit 1
  end
end
