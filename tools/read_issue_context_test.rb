require 'minitest/autorun'
require_relative 'read_issue_context'

class ReadIssueContextTest < Minitest::Test
  def test_current_excludes_contract_and_history
    body = "#{IssueContext::START}\n## Current task\nReady for review\n#{IssueContext::FINISH}\n## Contract\nlong contract"
    assert_equal "## Current task\nReady for review", IssueContext.current(body)
    assert_raises(RuntimeError) { IssueContext.current(body + IssueContext::START) }
    assert_raises(RuntimeError) { IssueContext.current('unmarked body') }
    assert_raises(RuntimeError) { IssueContext.current("#{IssueContext::FINISH}x#{IssueContext::START}") }
    assert_raises(RuntimeError) { IssueContext.current("#{IssueContext::START}\n#{IssueContext::FINISH}") }
  end

  def test_exact_section_includes_children_but_excludes_siblings_and_fenced_headings
    body = "# Design\n## Scope\na\n### Child\nb\n```md\n## Fake\n```\n## Evidence\nc\n"
    assert_equal ['Design', 'Scope', 'Child', 'Evidence'], IssueContext.headings(body).map(&:last)
    assert_equal "## Scope\na\n### Child\nb\n```md\n## Fake\n```", IssueContext.section(body, 'Scope')
    assert_raises(RuntimeError) { IssueContext.section(body, 'Missing') }
    assert_raises(RuntimeError) { IssueContext.section(body + "## Scope\nx", 'Scope') }
  end

  def test_conflicting_modes_and_invalid_identifiers_fail_before_network
    assert_raises(OptionParser::InvalidArgument) { IssueContext.run(['48', '--full', '--headings']) }
    assert_raises(RuntimeError) { IssueContext.run(['../48']) }
    assert_raises(RuntimeError) { IssueContext.run(['48', '--repo', 'owner/repo/extra']) }
  end

  def test_comment_from_another_issue_is_not_returned
    response = {'issue_url' => 'https://api.github.com/repos/kellyjanderson/readaloud/issues/49', 'body' => 'wrong issue'}
    assert_raises(RuntimeError) { IssueContext.validate_comment(response, 'kellyjanderson/readaloud', '48') }
    IssueContext.validate_comment(response, 'kellyjanderson/readaloud', '49')
  end
end
