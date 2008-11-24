require 'S3'
require 'EC2'
require 'SQS'
require 'SimpleDB'
require 'FPS'

# A module that groups together instances of the AWS infrastructure
# service clients, including S3, EC2, SQS, SimpleDB and FPS.
module PawsHelper

  CONFIG_FILE = File.join(RAILS_ROOT,'config','paws_config.yml')
  CONFIG = YAML.load_file(CONFIG_FILE)[RAILS_ENV] rescue {}
  # configuration via environment overrides config file
  CONFIG.merge!({
    'aws_access_key' => (ENV['AWS_ACCESS_KEY'] || CONFIG['aws_access_key']),
    'aws_secret_key' => (ENV['AWS_SECRET_KEY'] || CONFIG['aws_secret_key'])
  })

  if !CONFIG || [ CONFIG['aws_access_key'], CONFIG['aws_secret_key'] ].any?(&:blank?)
    STDERR.puts "To use PawsHelper, please configure 'aws_access_key' and 'aws_secret_key' in #{CONFIG_FILE} or your environment"
    exit 1
  end    

  if !CONFIG || [ CONFIG['s3_bucket'] ].any?(&:blank?)
    STDERR.puts "To use the marketplace, please configure 's3_bucket' in #{CONFIG_FILE} or your environment"
    exit 1
  end

  S3_BUCKET = CONFIG['s3_bucket']
  
  S3 = S3.new(CONFIG['aws_access_key'], CONFIG['aws_secret_key'])
  EC2 = EC2.new(CONFIG['aws_access_key'], CONFIG['aws_secret_key'])
  SQS = SQS.new(CONFIG['aws_access_key'], CONFIG['aws_secret_key'])
  SDB = SimpleDB.new(CONFIG['aws_access_key'], CONFIG['aws_secret_key'])
  FPS = FPS.new(CONFIG['aws_access_key'], CONFIG['aws_secret_key'])
  
end
