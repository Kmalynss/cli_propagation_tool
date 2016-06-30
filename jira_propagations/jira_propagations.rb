require 'jira'
require 'highline/import'
require 'pp'
require 'pry'

class JiraPropagation

  attr_reader :username, :password
  attr_accessor :task

  def initialize username, password
    @username = username
    @password = password
  end

  def client_options
    @client_options ||= {
      :username => username,
      :password => password,
      :site => "https://coupadev.atlassian.net/",
      :auth_type => :basic,
      :use_ssl => true,
      :context_path => ''
    }
  end

  def client
    @client ||= JIRA::Client.new(client_options)
  end

  def create_jira_sub_task jira_key, target_branches
    self.task = Task.new client, jira_key
    task.create_propagations target_branches
    task.move_to_in_progress
    task.propagations.map do |propagation|
      { sub_ticket_key: propagation.issue_key, target_branch: propagation.branch }
    end
  end

  def update_sub_tasks(sub_ticket_options)
    sub_ticket_options.each do |option|
      propagation = task.propagations.find {|propagation| propagation.issue_key == option[:key]}
      propagation.update_with_pr option[:url]
      propagation.move_to_code_review
    end
    task.move_to_code_propagation
  end


  class Task
    attr_reader :client, :issue_key, :propagations
    def initialize client, issue_key
      @client = client
      @issue_key = issue_key
    end

    def issue
      @issue ||= client.Issue.find(issue_key)
    end

    def create_propagations branches
      @propagations = branches.map do |branch|
        Propagation.create client: client, issue_key: issue_key, branch: branch
      end 
    end

    def move_to_in_progress
      if issue.status.name != "In Progress" && issue.status.name != "Code Propagation"
        transition = issue.transitions.build
        transition.save!("transition" => {"id" => 4})
      end
    end

    def move_to_code_propagation
      if issue.status.name != "Code Propagation"
        transition = issue.transitions.build
        transition.save!("transition" => {"id" => 521})
      end
      p "Jira sub tickets were successfully updated"
    end
  end

  class Propagation
    def self.create client:, issue_key:, branch:
      propagation =  self.new(client: client, parent_issue_key: issue_key, branch: branch).create
      propagation.move_to_in_progress
      propagation
    end
    
    attr_reader :client, :parent_issue_key, :branch

    def initialize client:, parent_issue_key:, branch:
      @client = client
      @parent_issue_key = parent_issue_key
      @branch = branch
    end

    def parent_issue
      client.Issue.find("#{parent_issue_key}")
    end

    def project
      client.Project.find("#{parent_issue_key[/\A\w+/]}")
    end

    def issue
      @issue ||= client.Issue.build
    end

    def issue_key
      issue.key
    end

    def create
      issue.save(params_to_create)
      issue.fetch
      self
    end

    def move_to_in_progress
      issue.transitions.build.save!("transition" => {"id" => 4})
    end

    def params_to_create
      {fields: {
        parent: {id: "#{parent_issue.id}"},
        project: {id: "#{project.id}"},
        summary: "Propagate #{parent_issue_key} in #{branch}",
        issuetype: {id: "10600"},
        description: "",
        customfield_12905: {'name' => "#{branch}"}
      }}
    end

    def update_with_pr pr_url
      issue.comments.build.save!(:body => "PR: #{pr_url}")
    end

    def move_to_code_review
      issue.transitions.build.save!("transition" => {"id" => 381})
    end

  end

end

#jira = JiraPropagation.new("CD-52443", ["014_6_release", "014_7_release"])
#options = jira.create_jira_sub_task

#option_hash = [{key: options[0][:sub_ticket_key], url: "http://www.google.com"}, {key: options[1][:sub_ticket_key], url: "http://www.google.com.ua"}]
#jira.update_sub_tasks(option_hash)
