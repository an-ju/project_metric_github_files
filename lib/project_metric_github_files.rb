require "project_metric_github_files/version"
require "octokit"
require "json"
require "open-uri"
require "date"

class ProjectMetricGithubFiles
  attr_reader :raw_data

  def initialize(credentials, raw_data = nil)
    @project_url = credentials[:github_project]
    @identifier = URI.parse(@project_url).path[1..-1]
    @client = Octokit::Client.new access_token: credentials[:github_access_token]
    @client.auto_paginate = true

    @raw_data = raw_data
  end

  def refresh
    @score = @image = nil
    @raw_data = commits.map(&:to_h)
  end

  def raw_data=(new)
    @raw_data = new
    @score = @image = nil
  end

  def score
    @raw_data ||= commits
    synthesize
    @score = @type_lines.each_value.reduce(&:+)
  end

  def image
    @raw_data ||= commits
    synthesize
    @image ||= { chartType: 'github_files',
                 titleText: 'Distribution of code changes among layers',
                 data: @type_lines }.to_json
  end

  def self.credentials
    %I[github_project github_access_token]
  end

  private

  def commits
    @client.commits_since(@identifier, Date.today - 7).map do |cmit|
      @client.commit(@identifier, cmit[:sha])
    end
  end

  def synthesize
    @raw_data ||= commits
    @type_files = @raw_data.flat_map { |cmit| cmit[:files] }.group_by { |f| file_type f }
    @type_lines = {}
    @type_files.each_pair do |key, val|
      @type_lines[key] = val.map { |cmit| cmit[:changes] }.reduce(&:+)
    end
  end

  def file_type(f)
    if %r{^app/models} =~ f[:filename]
      :model
    elsif %r{^app/controllers} =~ f[:filename]
      :controller
    elsif (%r{^app/views} =~ f[:filename]) || (%r{^app/assets} =~ f[:filename])
      :view
    elsif (%r{^spec/} =~ f[:filename]) || (%r{^features/} =~ f[:filename])
      :test
    elsif %r{^db/} =~ f[:filename]
      :db
    else
      :other
    end
  end
end
