# frozen_string_literal: true

# Usage:
#   GITHUB_TOKEN=xxxxxxx bundle exec ruby scan.rb ORGANIZATION_NAME

# jq でCSV作ろうと思ったがうまくいかない...
# ... | jq '.[] | [.full_name, .ruby_version, (.specs[] | select(.name == "rails").version)] | @csv'

require 'octokit'
require 'bundler'
require 'json'

class Scanner
  attr_reader :client, :org_name, :repos

  def initialize(org_name, token)
    @client = Octokit::Client.new(access_token: token)
    @org_name = org_name
    fetch_repos
  end

  def fetch_repos
    org = client.organization(org_name)
    private_repo_count = org[:total_private_repos]
    public_repo_count = org[:public_repos]
    repo_count = private_repo_count + public_repo_count
    req_count = (repo_count + 99) / 100
    @repos = []
    (1..req_count).each do |page|
      @repos += client.organization_repositories(org_name, page: page, per_page: 100, sort: 'full_name')
    end
    @repo_hash = @repos.map { |r| [r.full_name, r] }.to_h
  end

  def scan_ruby_version(repo_name)
    content = client.contents(repo_name, path: '.ruby-version')
    Base64.decode64(content.content).chomp
  rescue Octokit::NotFound
    nil
  end

  def spec_data(spec)
    {
      name: spec.name,
      version: spec.version.to_s,
      dependencies: spec.dependencies.map { |d| {name: d.name, requirement: d.requirement.to_s} },
    }
  end

  def source_data(source)
    {
      name: source.name,
      uri: source.uri,
      revision: source.revision,
    }
  end

  def sources_data(sources)
    sources
      .select { |s| s.is_a?(Bundler::Source::Git) }
      .map { |s| source_data(s) }
  end

  def scan(repo_name)
    content = client.contents(repo_name, path: 'Gemfile.lock')
    lockfile = Bundler::LockfileParser.new(Base64.decode64(content.content))
    spec_hash = lockfile.specs.map { |s| [s.name, s] }.to_h

    {
      full_name: repo_name,
      ruby_version: scan_ruby_version(repo_name),
      dependencies: lockfile.dependencies.keys,
      specs: lockfile.specs.map { |s| spec_data(s) },
      sources: sources_data(lockfile.sources),
    }
  end

  def scan_all
    @repos.map do |repo|
      STDERR.puts "****** #{repo.full_name}"
      begin
        scan(repo.full_name)
      rescue Octokit::NotFound => e
        # STDERR.puts e.message
      rescue Bundler::LockfileError => e
        # STDERR.puts e.message
      end
    end.compact
  end
end

org_name = ARGV[0]
scanner = Scanner.new(org_name, ENV['GITHUB_TOKEN'])
puts scanner.scan_all.to_json
