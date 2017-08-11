#!/usr/bin/env ruby

require 'aws-sdk'
require 'cheetah'   # https://github.com/openSUSE/cheetah
require 'colorize'
require 'json'
require 'optparse'  
require 'pp'
require 'securerandom'
require 'yaml'

#add-user-to-group

def get_usernames
  return $iam.list_users.users.map{|u| u.user_name }
end

def get_user_groupnames(username)
  reply = $iam.list_groups_for_user(user_name: username)
  return reply.groups.map{|g| g.group_name}
end

def create_password
  # This will create the password
  # Check the policy for required characters:
  # aws iam get-account-password-policy
   
  # Created string will be about 4/3 of 128
  s = SecureRandom.urlsafe_base64(128)

  s = s[0..127]

  # Still the password policy requires symbols, let's create and add a few
  symbols = ['%', '+']

  count = SecureRandom.random_number(20)
  (1..count).each do |i|
    pos = SecureRandom.random_number(s.size)
    s[pos] = symbols[SecureRandom.random_number(symbols.count)]
  end
  return s
end

def create_user(username)
  begin
    reply = $iam.create_user(user_name: username)
    $iam.wait_until(:user_exists, user_name: username)
    return reply.user
  rescue Aws::IAM::Errors::EntityAlreadyExists
    puts "Aborting, user already exists: #{username}".red
    exit
  end
end

def create_access_keys_for_user (username)
  begin
    key = $iam.create_access_key(user_name: username)
    return key.access_key
  rescue => e
    puts e.message.red
    return nil
  end
end

def create_password_for_user (username)
  pwd = create_password
  begin
    reply = $iam.create_login_profile(password: pwd, user_name: username, password_reset_required: false)
    return pwd
  rescue => e
    puts e.message.red
    puts "Aborted.".red
    exit
  end
end

def copy_permissions (user_source, username)
  groupnames = get_user_groupnames( user_source )
  groupnames.each do |g|
    begin
      $iam.add_user_to_group(user_name: username, group_name: g)
    rescue => e
      puts e.message.red
    end
  end
end

begin
  $iam = Aws::IAM::Client.new

  $options = {}
  optparse = OptionParser.new do |opts|
    opts.banner = "Usage: #{File.basename($0)} [options]"
    $options[:nocolor] = false
    opts.on( '-C', '--no-color', "Don't color the output" ) do
      $options[:nocolor] = true
      String.disable_colorization true
    end

    $options[:mail] = ""
    opts.on( '-m', '--mail STRING', "Email address" ) do |s|
      $options[:mail] = s
    end

    $options[:template] = ""
    opts.on( '-t', '--template STRING', "Username providing template for groups" ) do |s|
      $options[:template] = s
    end

    $options[:username] = ""
    opts.on( '-u', '--username STRING', "Username" ) do |s|
      $options[:username] = s
    end

    $options[:help] = ""
    opts.on( '-h', '--help', "Show this help text" ) do 
      puts opts
      exit
    end
  end
  optparse.parse!

  Random.new_seed

  # Read configuration
  configuration = YAML.load_file( "#{ENV['HOME']}/.aws-helper/aws-helper.yaml" )

  username = $options[:username]

  if username.empty?
    puts "Please provide username with '-u'"
    exit
  end

  # Get existing users
  usernames = get_usernames
  puts "Existing users: #{usernames.count}"
    
  # Check if user exists
  if usernames.include? username
    puts "User already exists: #{username}"
  else
    user = create_user( username )
    if user.empty?
      puts "Failed to create #{username}"
      exit
    else
      puts "Created: #{ user.arn}".green
    end
  end


  if $options[:mail].empty?
    puts "No mail address set, won't create password and access keys".red
  else
    # Create password
    password = create_password_for_user( username )
    if !password.empty?
      puts "Created password for #{username}".green
    end

    # Create access keys
    keys = create_access_keys_for_user( username )
    #puts "Access key: #{keys.access_key_id}".blue
    #puts "Secret key: #{keys.secret_access_key}".blue
    if !keys.empty?
      puts "Created access keys for #{username}".green
    end
  end

  if !$options[:template].empty?
    # Copy groups from user
    copy_permissions($options[:template] , username)

    puts "Groups of #{username}:"
    puts groupnames = get_user_groupnames( username )
  end

  if !$options[:mail].empty?
    # Read template
    template_filename = configuration["create_accounts"]["mail_template"]
    file = File.open(template_filename)
    mail_body = file.read

    # Insert into template
    mail_body.sub!( "USERNAME", username) 
    mail_body.sub!( "PASSWORD", password) 
    mail_body.sub!( "KEYPAIR", "#{keys.access_key_id} #{keys.secret_access_key}")
    
    # Write body to tmpfile
    tmp_file = "/tmp/mail.txt"
    File.write(tmp_file, mail_body)

    # Mail tmpfile (using mutt)    
    mail_cmd = configuration["create_accounts"]["mail_cmd"].split(" ")
    subject  = configuration["create_accounts"]["mail_subject"]
    bcc      = configuration["create_accounts"]["mail_bcc"]
    mail_cmd.each  do |c|
      c.sub!( "SUBJECT", subject)
      c.sub!( "BCC", bcc)
      c.sub!( "ADDRESS", $options[:mail] )
    end

    begin
      Cheetah.run(["cat", tmp_file], mail_cmd)
      puts "Mailed credentials to #{$options[:mail]}".green
    rescue => e
      puts e.message.red
    end

    # Delete tmpfile
    File.delete tmp_file
  end
end
