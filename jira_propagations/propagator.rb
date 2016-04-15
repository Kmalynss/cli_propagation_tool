require 'highline'
require 'yaml'

require_relative 'jira_propagations'
require_relative 'git_propagations'

module Propagator
  class CLI
    attr_reader :reviewers
    def initialize reviewers
      @reviewers = reviewers
    end

    def cli
      @cli ||= ::HighLine.new
    end

    def jira_ticket_key
      cli.ask('Set jira ticket key:')
    end
    
    def target_branch_names
      cli.ask('Please Specify target branches(comma separated list):', lambda {|raw| raw.split(/,\s*/) })
    end

    def reviewer_lvl_1
      puts 'Choose 1st level reviewer:'
      cli.choose(reviewers.first)
    end

    def reviewer_lvl_2
      puts 'Choose 2nd level reviewer:'
      cli.choose(reviewers.second)
    end

    def risk_level
      puts 'Choose risk level'
      cli.choose(1,2,3,4,5)
    end

    def summary_of_issue
      cli.ask('Specify summary of issue:')
    end

    def summary_of_change
      cli.ask('Specify summary of change:')
    end

    def testing_approach
      cli.ask('Specify testing approach:')
    end

    def poll_user
      OpenStruct.new({
        :jira_ticket_key => jira_ticket_key,
        :target_branch_names => target_branch_names,
        :reviewer_lvl_1 => reviewer_lvl_1,
        :reviewer_lvl_2 => reviewer_lvl_2,
        :risk_level => risk_level,
        :summary_of_issue => summary_of_issue,
        :summary_of_change => summary_of_change,
        :testing_approach => testing_approach
      })
    end
  end
end

module Propagator
  class << self

    def params_to_create_propagations user_data
      return user_data.jira_ticket_key, user_data.target_branch_names
    end


    def params_to_create_prs user_data, jira_propagation_result
      result = {:branches => {}}
      jira_propagation_result.each do |pair|


        result[:branches]["#{pair[:target_branch]}_#{user_data.jira_ticket_key}"] = {
          :jira_main_link => "https://coupadev.atlassian.net/browse/#{user_data.jira_ticket_key}",
          :jira_propagation_link => "https://coupadev.atlassian.net/browse/#{pair[:sub_ticket_key]}",
          :base_branch => pair[:target_branch],
          :title => "#{user_data.jira_ticket_key} #{pair[:sub_ticket_key]} #{pair[:target_branch]}"
        }
      end

      result[:summary_of_issue] = user_data.summary_of_issue
      result[:summary_of_change] = user_data.summary_of_change
      result[:testing_approach] = user_data.testing_approach
      result[:reviewers] = [user_data.reviewer_lvl_1, user_data.reviewer_lvl_2]
      result[:risk_level] = user_data.risk_level
      result[:description_template] = pr_description_template
      result

    end

    def pr_description_template
      File.open('pr_description.md.erb') {|f| f.read }
    end

    def params_to_populate_prs_to_subtasks tasks_to_pr_ids
      tasks_to_pr_ids.each_pair.map do |ticket_key, pr_url|
        {:key => ticket_key, :url => pr_url} 
      end
    end

    def params_to_update_prs jira_propagation_result, propagation_tasks_to_pr_ids
      propagation_tasks_to_pr_ids.map do |branch_to_pr_url|
        {
          :url => branch_to_pr_url.values.first,
          :key => jira_propagation_result.find { |p1| p1[:target_branch] ==  branch_to_pr_url.keys.first  }[:sub_ticket_key]
        }
      end
    end

    def propagate user_data, github_client, jira_client
      p params_to_create_propagations(user_data)
      jira_propagation_result = jira_client.create_jira_sub_task *params_to_create_propagations(user_data)

      p  params_to_create_prs(user_data, jira_propagation_result)
      propagation_tasks_to_pr_ids = github_client.create_pr params_to_create_prs(user_data, jira_propagation_result)
  
      p params_to_update_prs(jira_propagation_result, propagation_tasks_to_pr_ids)
      jira_client.update_sub_tasks params_to_update_prs(jira_propagation_result, propagation_tasks_to_pr_ids)
    end
  end
end

config = YAML.load_file('propagations.yml')
reviewers = OpenStruct.new config['reviewers']
jira = OpenStruct.new config['jira']
git = OpenStruct.new config['git']

Propagator.propagate Propagator::CLI.new(reviewers).poll_user, GitPropagation.new(git.token), JiraPropagation.new(jira.username, jira.password)



