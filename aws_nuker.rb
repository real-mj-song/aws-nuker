#!/usr/bin/env ruby

require 'optparse'
require 'aws-sdk-ec2'
require 'aws-sdk-s3'

class AWSNuker
  BATCH_SIZE = 300

  def initialize
    parse
    verify_args
  end

  # Public methods
  def run
    puts "#{"="*20}DRY RUN STARTED" if @options[:dry_run]

    case @options[:service]
    when "ec2"
      ec2_termination
    when "s3"
      s3_termination
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
    early_exit('instance')

    if instances.count > 0
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
    end
    puts "\nAll instances got terminated!"

    destroy_ec2_snapshots(ec2)
    puts "\nAll done!"
  end

  private def s3_termination
    # show what will be deleted
    s3 = Aws::S3::Client.new(profile: @options[:profile], region: @options[:region])
    resp = s3.list_buckets
    puts "* The following buckets will be deleted =>"
    buckets = resp.buckets
    buckets.each do |bucket|
      puts "#{bucket.name}"
    end

    # exit here if desired
    early_exit('bucket')

    buckets.each do |bucket|
      begin
        resp = s3.delete_bucket({ bucket: bucket.name })
      rescue Aws::S3::Errors::BucketNotEmpty
        puts "FAILURE: Bucket '#{bucket.name}' is not empty. Setting a lifecycle policy to destroy all objects inside the bucket by tomorrow."
        puts "\tPlease run the script again tomorrow."
        resp = s3.put_bucket_lifecycle_configuration({
          bucket: bucket.name, 
          lifecycle_configuration: {
            rules: [
              {
                expiration: {
                  days: 1, 
                },
                prefix: nil,
                filter: {
                  prefix: "", 
                },
                id: "DeleteAll", 
                status: "Enabled",
                noncurrent_version_expiration: {
                  noncurrent_days: 1,
                },
                abort_incomplete_multipart_upload: {
                  days_after_initiation: 1,
                },
              }, 
            ], 
          },
        })
      rescue Aws::S3::Errors::ServiceError => e
        puts "ERROR: #{e}"
        puts "\tAttempting to delete bucket '#{bucket.name}' errored."
        puts "\tTry deleting it manually."
      else
        puts "SUCCESS: Bucket '#{bucket.name}' got deleted successfully."
      end
    end
  end

  def destroy_ec2_snapshots(client)
    resp = client.describe_snapshots({
      owner_ids: ["self"],
    })
    puts "* The number of snapshots to be deleted =>"
    puts resp.snapshots.count

    puts "Deleting #{BATCH_SIZE} snapshots at a time."
    resp.snapshots.lazy.each_slice(BATCH_SIZE) do |batch|
      batch.each do |snapshot|
        client.delete_snapshot({
          snapshot_id: snapshot.snapshot_id,
        })
      end
      p "."
    end
    puts "\nAll snapshots got deleted!"
  end

  private def early_exit(service_obj)
    puts
    service_name = service_obj
    # exit here if desired
    if @options[:dry_run]
      puts "#{"="*20}DRY RUN ENDED"
      exit 0
    end
    puts "Are you sure that you want to terminate/delete all #{service_name}s above? (YES/NO)"
    if gets.chomp.upcase != 'YES'
      puts "Exiting..."
      exit 0
    end
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
