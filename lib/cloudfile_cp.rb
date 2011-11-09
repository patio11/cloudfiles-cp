require 'rubygems'
require 'cloudfiles'
require 'optparse'
require 'yaml'
require 'find'
require 'pathname'

DEFAULT_KEY_FILE = "~/.rackspace_cloud_credentials"

CREDENTIAL_FILENAME = File.expand_path(DEFAULT_KEY_FILE)

@options = {}

optparse = OptionParser.new do |opts|
  opts.banner = "Backup specified files to Rackspace Cloud Files.\nUsage: ruby cloudfile-cp.rb [@options] file1 [file2...]"

  @options[:recursive] = false
  opts.on('-r', '--recursive', 'Recursively follow directories.') do
    @options[:recursive] = true
  end

  @options[:include_hidden] = false
  opts.on('-h', '--include-hidden', 'Copy files/directories beginning with , too.  (implies -r)') do
    @options[:include_hidden] = @options[:recursive] = true
  end

  @options[:username] = nil
  opts.on('-u USER', '--user USER', 'specify user (default: reads in #{DEFAULT_KEY_FILE})') do |username|
    @options[:username] = username
  end

  opts.on('-c CREDENTIAL_FILE', '--credentials CREDENTIAL_FILE', 'load YAML file containing "key: RACKSPACE_KEY_GOES HERE" and "bucket_name: BUCKET_NAME_GOES_HERE"') do |cred_file|
    CREDENTIAL_FILENAME = File.expand_path(cred_file)
  end

  opts.on('-k KEY', '--key KEY', 'specify Rackspace API key (default: reads in #{DEFAULT_KEY_FILE} and looks for key:)') do |key|
    @options[:key] = key
  end

  @options[:bucket_name] = nil
  opts.on('-b BUCKET_NAME', '--bucket BUCKET_NAME', 'specify bucket to back file up to (default: reads YAML in #{DEFAULT_KEY_FILE} and looks for bucket_name:)') do |bucket_name|
    @options[:bucket_name] = bucket_name
  end

  @options[:verbose] = false
  opts.on('-v', '--verbose', "The output of the script gets very chatty.") do
    @options[:verbose] = true
  end

  @options[:overwrite] = false
  opts.on('-f', '--force', "Overwrite files with the same name. (defaults to skipping them if you don't specify this flag)") do
    @options[:overwrite] = true
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
  @options[:key] ||= creds[:key] || creds["key"]
  @options[:bucket_name] ||= creds[:bucket_name] || creds["bucket_name"]
  @options[:username] ||= creds[:user] || creds["user"]
end


unless @options[:username]
  puts "You have to specifiy a Rackspace user name, either with the -u or --user command line switch, or by writing to #{DEFAULT_KEY_FILE} (a YAML file, expects key:, bucket_name:, and user:)"
  exit 1
end

unless @options[:key]
  puts "You have to specifiy a Rackspace API key, either with the -k or --key command line switch, or by writing to #{DEFAULT_KEY_FILE} (a YAML file, expects key:, bucket_name:, and user:)"
  exit 1
end

unless @options[:bucket_name]
  puts "You have to specifiy a Rackspace bucket name, either with the -b or --bucket command line switch, or by writing to #{DEFAULT_KEY_FILE} (a YAML file, expects key:, bucket_name:, and user:)"
  exit 1
end


files = ARGV

if (files.empty?)
  puts optparse.banner
  exit 1
end



cf = CloudFiles::Connection.new(:username => @options[:username], :api_key => @options[:key])

puts "Listing all your containers"

buckets = cf.containers

bucket_name = @options[:bucket_name]

if buckets.include? bucket_name
  puts "Found the bucket #{bucket_name}" if @options[:verbose]
else
  puts "Did not find the bucket #{bucket_name}.  Creating it..." if @options[:verbose]
  cf.create_container(bucket_name)
  puts "  Done creating bucket." if @options[:verbose]
end

container = cf.container(bucket_name)

def upload_file_to_bucket(container, bucket_filename)
  if (container.object_exists?(bucket_filename) && !@options[:overwrite])
    puts "  Already have #{bucket_filename} in bucket.  Skipping." if @options[:verbose]
  else
    object = container.create_object(bucket_filename, true)
    puts "  Beginning upload of #{bucket_filename}" if @options[:verbose]
    object.write(File.read(bucket_filename))
    puts "    Upload complete" if @options[:verbose]
  end
  
end

files.each do |file|
  puts "Considering: #{file} from command line"
  if (@options[:recursive])
    Find.find(File.expand_path(file)) do |expanded_file|
      if (File.basename(expanded_file)[0..0] == '.')
        if (!@options[:include_hidden])
          Find.prune
        else
          #next
        end
      else
        #next
      end

      #If we got this far, file is fair game.
      if !File.directory?(expanded_file)
        bucket_filename = Pathname.new(expanded_file).relative_path_from(Pathname.getwd).to_s
        upload_file_to_bucket(container, bucket_filename)
      else
        puts "Skipping directory #{expanded_file}" if @options[:verbose]
      end
    end
  else
    filename = File.expand_path(file)
    if File.exist?(filename) and !File.directory?(filename)
      bucket_filename = Pathname.new(filename).relative_path_from(Pathname.getwd).to_s
      upload_file_to_bucket(container, bucket_filename)
    else
      puts "You attempted to sync a file which does not exist: #{filename}"
      exit 128
    end
  end

  puts "All done!" if @options[:verbose]
end
