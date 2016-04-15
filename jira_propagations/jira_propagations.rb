require 'jira'
require 'highline/import'
require 'pp'
require 'pry'

class JiraPropagation
  attr_reader :username, :password
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

  def update_sub_tasks(sub_ticket_options)
    parent_jira_sub_ticket_id = ''
    sub_ticket_options.each do |option|
      jira_sub_ticket = client.Issue.find("#{option[:key]}")
      comment = jira_sub_ticket.comments.build
      comment.save!(:body => "PR #{option[:url]}")
      transition = jira_sub_ticket.transitions.build
      transition.save!("transition" => {"id" => 381})
      parent_jira_sub_ticket_id = jira_sub_ticket.parent['id']
    end
    parent_jira_sub_ticket = client.Issue.find("#{parent_jira_sub_ticket_id}")
    if parent_jira_sub_ticket.status.name != "Code Propagation"
      transition = parent_jira_sub_ticket.transitions.build
      transition.save!("transition" => {"id" => 521})
    end
    p "Jira sub tickets were successfully updated"
  end

  def create_jira_sub_task jira_key, target_branches
    jira_ticket = client.Issue.find("#{jira_key}")
    jira_project = client.Project.find("#{jira_key[/\A\w+/]}")

    @new_sub_tickets = target_branches.map do |target_branch|
      sub_ticket = client.Issue.build
      sub_ticket.save({fields: {parent: {id: "#{jira_ticket.id}"}, project: {id: "#{jira_project.id}"}, summary: "Propagate #{jira_key} in #{target_branch}", issuetype: {id: "10600"}, description: "", customfield_12905: {'name' => "#{target_branch}"}}})
      sub_ticket.fetch

      transition = sub_ticket.transitions.build
      transition.save!("transition" => {"id" => 4})
      {sub_ticket_key: sub_ticket.key, target_branch: target_branch}
    end

    if jira_ticket.status.name != "In Progress" && jira_ticket.status.name != "Code Propagation"
      transition = jira_ticket.transitions.build
      transition.save!("transition" => {"id" => 4})
    end

    @new_sub_tickets
  end
end

#jira = JiraPropagation.new("CD-52443", ["014_6_release", "014_7_release"])
#options = jira.create_jira_sub_task

#option_hash = [{key: options[0][:sub_ticket_key], url: "http://www.google.com"}, {key: options[1][:sub_ticket_key], url: "http://www.google.com.ua"}]
#jira.update_sub_tasks(option_hash)
