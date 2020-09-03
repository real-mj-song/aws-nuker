#!/usr/bin/env ruby

require 'optparse'
require 'aws-sdk-ec2'
require 'aws-sdk-s3'

class AWSNuker 
  def initialize
    parse
    verify_args
  end

  # Public methods
  def run
    case @options[:service]
    when "ec2"
      ec2_termination
    else
      raise ArgumentError.new("#{@options[:service]} is not a supported service.")
    end
  end

  # Private methods
  private def ec2_termination
    # show what will be deleted
    ec2 = Aws::EC2::Client.new(profile: @options[:profile], region: @options[:region])
    resp = ec2.describe_instances({
      filters: [
        {
          name: "instance-state-name", 
          values: ["running", "stopped", "stopping", "pending"], 
        }, 
      ], 
    })
    puts "* The following instances will be deleted =>"
    instances = resp.reservations.map(&:instances).flatten(1)
    instances.each do |instance|
      puts "#{instance.instance_id.ljust(20)} #{instance.instance_type.ljust(20)} #{instance.state.name}"
    end

    # exit here if desired
    if @options[:dry_run]
      puts "#{"="*20}DRY RUN ENDED"
      exit 0
    end
    puts "Are you sure that you want to terminate all instances above? (YES/NO)"
    if gets.chomp.upcase != 'YES'
      puts "Exiting..."
      exit 0
    end

    # Turn off instance termination protection if enabled
    protected_instances = instances.filter do |instance|
      ec2.describe_instance_attribute({attribute: "disableApiTermination", instance_id: instance.instance_id }).disable_api_termination
    end
    protected_instances.each do |instance|
      ec2.modify_instance_attribute({
        instance_id: instance.instance_id,
        disable_api_termination: {
          value: false,
        }
      })
    end
    ec2.terminate_instances({
      instance_ids: instances.map(&:instance_id)
    })
    puts "\nAll done!"
  end

  private def verify_args
    required_options = [:profile, :region, :service]

    all_options_exist = required_options.inject(true) {|bool, curr| bool && @options.has_key?(curr) }
    raise ArgumentError.new("All of #{required_options} are required.") unless all_options_exist
  end

  private def parse
    @options = {}
    OptionParser.new do |opts|
      opts.banner = "Usage: aws_nuker.rb [options]"
      
      opts.on("-p", "--profile PROFILE", "AWS profile name") do |o|
        @options[:profile] = o
      end
      opts.on("-r", "--region REGION", "AWS region") do |o|
        @options[:region] = o
      end
      opts.on("-s", "--service SERVICE", "AWS service name. Supported services are: ['ec2', 's3']") do |o|
        @options[:service] = o
      end
      opts.on("-d", "--[no-]dry-run", "Dry run") do |o|
        @options[:dry_run] = o
      end
      opts.on("-h", "--help", "Print this help") do
        puts opts
        exit
      end
    end.parse!
  end
end

AWSNuker.new.run
