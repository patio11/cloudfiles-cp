require 'rubygems'
require 'cloudfiles'
require 'optparse'
require 'yaml'
require 'find'
require 'pathname'

CREDENTIAL_FILENAME = File.expand_path("~/.rackspace_cloud_credentials")

options = {}

optparse = OptionParser.new do |opts|
  opts.banner = "Backup specified files to Rackspace Cloud Files.\nUsage: ruby backup_to_cloud.rb [options] file1 [file2...]"

  options[:recursive] = false
  opts.on('-r', '--recursive', 'Recursively follow directories.') do
    options[:recursive] = true
  end

  options[:include_hidden] = false
  opts.on('-h', '--include-hidden', 'Copy files/directories beginning with , too.  (implies -r)') do
    options[:include_hidden] = options[:recursive] = true
  end

  options[:username] = nil
  opts.on('-u USER', '--user USER', 'specify user (default: reads in ~/.rackspace_cloud_credentials)') do |username|
    options[:username] = username
  end

  opts.on('-c CREDENTIAL_FILE', '--credentials CREDENTIAL_FILE', 'load YAML file containing "key: RACKSPACE_KEY_GOES HERE" and "bucket_name: BUCKET_NAME_GOES_HERE"') do |cred_file|
    CREDENTIAL_FILENAME = File.expand_path(cred_file)
  end

  opts.on('-k KEY', '--key KEY', 'specify Rackspace API key (default: reads in ~/.rackspace_cloud_credentials and looks for key:)') do |key|
    options[:key] = key
  end

  options[:bucket_name] = nil
  opts.on('-b BUCKET_NAME', '--bucket BUCKET_NAME', 'specify bucket to back file up to (default: reads YAML in ~/.rackspace_cloud_credentials and looks for bucket_name:)') do |bucket_name|
    options[:bucket_name] = bucket_name
  end

  opts.on('-h', '--help', 'display this screen') do
    puts opts
    exit
  end
end

optparse.parse!

if (File.exist? CREDENTIAL_FILENAME)
  creds = YAML.load(File.open(CREDENTIAL_FILENAME))
  puts creds.inspect
  options[:key] ||= creds[:key] || creds["key"]
  options[:bucket_name] ||= creds[:bucket_name] || creds["bucket_name"]
  options[:username] ||= creds[:user] || creds["user"]
end


unless options[:username]
  puts "You have to specifiy a Rackspace bucket name, either with the -u or --user command line switch, or by writing to ~/.rackspace_cloud_key (a YAML file, expects key:, bucket_name:, and user:)"
  exit 1
end

unless options[:key]
  puts "You have to specifiy a Rackspace API key, either with the -k or --key command line switch, or by writing to ~/.rackspace_cloud_key (a YAML file, expects key:, bucket_name:, and user:)"
  exit 1
end

unless options[:bucket_name]
  puts "You have to specifiy a Rackspace bucket name, either with the -b or --bucket command line switch, or by writing to ~/.rackspace_cloud_key (a YAML file, expects key:, bucket_name:, and user:)"
  exit 1
end


files = ARGV

if (files.empty?)
  puts optparse.banner
  exit 1
end



cf = CloudFiles::Connection.new(:username => options[:username], :api_key => options[:key])

puts "Listing all your containers"

buckets = cf.containers

bucket_name = options[:bucket_name]

if buckets.include? bucket_name
  puts "Found the bucket #{bucket_name}"
else
  puts "Did not find the bucket #{bucket_name}.  Creating it..."
  cf.create_container(bucket_name)
  puts "  Done creating bucket."
end

container = cf.container(bucket_name)

files.each do |file|
  puts "Considering: #{file} from command line"
  if (options[:recursive])
    Find.find(File.expand_path(file)) do |expanded_file|
      puts File.relative_path(expanded_file)
    end
  else
    filename = File.expand_path(file)
    if File.exist?(filename) and !File.directory?(filename)
      bucket_filename = Pathname.new(filename).relative_path_from(Pathname.getwd).to_s
      puts "We can upload that! #{bucket_filename}"
      if (container.object_exists?(bucket_filename) && !options[:overwrite])
        puts "  Already have #{bucket_filename} in bucket.  Skipping."
      else
        #Upload it
        object = container.create_object(bucket_filename, true)
        puts "  Beginning upload of #{filename}"
        object.write(File.read(filename))
        puts "    Upload complete"
      end
    else
      puts "You attempted to sync a file which does not exist: #{filename}"
      exit 128
    end
  end
end