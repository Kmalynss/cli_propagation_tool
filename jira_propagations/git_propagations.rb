require 'octokit'
require 'pry'

class GitPropagation
  DEFAULT_REPO = "coupa/coupa_development"
  DEFAULT_LABELS = ["needs review"]

  attr_accessor :access_token
  def initialize access_token
    @access_token = access_token
  end

  def client
    @client ||= Octokit::Client.new(:access_token => access_token)
  end

  class PullRequest
    attr_reader :client, :title, :description, :base_branch, :head_branch, :risk_level, :saved
    def initialize client, data
      @client = client
      @base_branch = data[:base_branch]
      @head_branch = data[:head_branch]
      @title = data[:title]
      @description = data[:decsription]
      @risk_level = data[:risk_level]
    end


    def save
      begin
       @saved = client.create_pull_request(DEFAULT_REPO, base_branch, head_branch, title, description)
      rescue Octokit::UnprocessableEntity
        puts "Can't create a PR to the #{base_branch} from #{head_branch}. Maybe you already created it?"
        return false
      end
    end
    

    def saved?
      saved.present?
    end

    def number
      saved['number']
    end

    def url
      saved['html_url']
    end

    def labels
       DEFAULT_LABELS + ["risk level #{risk_level}" ]
    end

    def add_labels
      client.add_labels_to_an_issue(DEFAULT_REPO, number, labels)
    rescue Octokit::NotFound
      puts "Can't add a label"
    end
  end

  class PrDescription

    DESCRIPTION_TEMPLATE = File.open('pr_description.md.erb') {|f| f.read }
    attr_reader :summary_of_issue, :summary_of_change, :testing_approach, :reviewers, :jira_main_link, :jira_propagation_link

    def initialize data
      @summary_of_issue = data[:summary_of_issue]
      @summary_of_change = data[:summary_of_change]
      @testing_approach = data[:testing_approach]
      @reviewers = data[:reviewers]
      @jira_main_link = data[:jira_main_link]
      @jira_propagation_link = data[:jira_propagation_link]
    end

    def render
      ERB.new(DESCRIPTION_TEMPLATE).result(binding)
    end
  end

  def create_prs(test_hash)
    created_pull_requests = []
    test_hash[:branches].keys.each do |head_branch|
      pr_hash = {}

      base_branch = test_hash[:branches][head_branch][:base_branch]
      description = PrDescription.new(
        :summary_of_issue => test_hash[:summary_of_issue],
        :summary_of_change => test_hash[:summary_of_change],
        :testing_approach => test_hash[:testing_approach],
        :reviewers => test_hash[:reviewers],
        :jira_main_link => test_hash[:branches][head_branch][:jira_main_link],
        :jira_propagation_link => test_hash[:branches][head_branch][:jira_propagation_link],
      )
      pr = PullRequest.new(client,
        :head_branch => head_branch,
        :base_branch => test_hash[:branches][head_branch][:base_branch],
        :title => test_hash[:branches][head_branch][:title],
        :description => description,
        :risk_level => test_hash[:risk_level]
      )

      if pr.save
        pr.add_labels
        created_pull_requests << { base_branch => pr.url }
      end
    end

    created_pull_requests
  end


end

# test_hash = {
#   branches: {
#     "014_release_test_cli_propagation" => {
#       jira_main_link: "http://jira.com",
#       jira_propagation_link: "http://jira.com",
#       base_branch: '014_release',
#       title: 'title',
#     },
#   },
#   reviewers: ['dlandberg', 'dlandberg'],
#   description: 'description',
#   risk_level: "1"
# }

# git = GitPropagation.new
# hash = git.create_pr(test_hash)
# puts hash
