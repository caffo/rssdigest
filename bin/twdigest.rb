#!/usr/bin/env ruby
# twdig.rb - a twitter to email digest daemon
# non-copyright (c) 2008 rodrigo franco <caffo@imap.cc>

$:.unshift(File.dirname(__FILE__) + '/../lib')
require 'ssl'
require 'utils'

# Required Gems
require 'rubygems'
require "simpleconsole"
require 'rubygems'
require 'active_record' #(sqlite3)
require 'twitter' #(twitter4r)
require 'action_mailer'
require 'openssl'

# Non Gems required libs
require 'time'
require 'pathname'



# Configuration Variables
TWITTER_USERNAME = 'foo'
TWITTER_PASS     = 'bar'

EMAIL_ADDRESS    = 'foobar@gmail.com'
SMTP_SERVER      = 'smtp.gmail.com'
SMTP_PORT        = 587

SMTP_USER        = 'foo'
SMTP_PASS        = 'bar'

# Application Code
class Controller < SimpleConsole::Controller
  params :string => {:e => :exec}
  
  
  def default
    puts "\n"    
    puts "--------"    
    puts "twdig.rb"
    puts "--------"
    puts "\n"
    puts "a twitter to email digest daemon. experimental code, no warranty or"
    puts "guarantee it will work. it may blow your computer and your house!"
    puts "\n"
    puts "valid options are:"
    puts "\n"
    puts "\t * database -e [create|destroy]"
    puts "\t * retrieve"
    puts "\t * status "
    puts "\t * digest -e [preview|send]"
    puts "\n"
    puts "------"
    puts "setup"
    puts "------"
    puts "\n"
    puts "\t* Edit the configuration variables and run 'twdig.rb setup'"
    puts "\t* If everything goes OK, follow the instructions after the setup execution. If not, see manual setup."
    puts "\n"
    puts "-------------"
    puts "manual setup"
    puts "-------------"
    puts "\n"
    puts "\t* Create the database using 'twdig.rb database -e create'"
    puts "\t* Test the retrieval using 'twdig.rb retrieve'"
    puts "\t* Preview the digest using 'twdig.rb digest preview'"
    puts "\t* Test the email sending using 'twdig.rb digest send'"
    puts "\t* Check your email"
    puts "\t* Add the following cronjobs in your server:"
    puts "\n"
    puts "\t\t 10 * * * *  #{$0} retrieve"
    puts "\t\t 59 23 * * * #{$0} digest -e mail"
    puts "\n"    
    puts "\t - Done :-)"
    puts "\n"
  end
  
  # deals with database related functionality
  # including create and destroy the database.
  def database    
    case params[:exec]
    when "create"
      # define a migration
      CreateTweets.migrate(:up)
    when "destroy"
      CreateTweets.migrate(:down)
    else
      puts "valid options: database -e [create | destroy]"
    end
  end

  # retrieve the tweets from the remote API
  # and store them in our database
  def retrieve
    client = Twitter::Client.new(:login => TWITTER_USERNAME, :password => TWITTER_PASS)
    timeline = client.timeline_for(:friends)
    timeline.each do |tw|
      next if Tweet.find_by_remote_id(tw.id)
      t = Tweet.new
      t.message     = tw.text
      t.remote_id   = tw.id
      t.screen_name = tw.user.screen_name
      t.save
    end
  end
  
  # prints the total tweets that will be sent
  # in the next digest sending
  def status
    puts "#{Tweet.find(:all).size} tweets in the queue."
  end
  
  # deal with the email, generating and sending the
  # digests to the user
  def digest
      d = String.new
      Tweet.find(:all).each do |t|
        next if t.created_at.to_date != Date.today
        d << "<#{t.screen_name}> #{t.message}\n\n"
      end
      d << "\n"
    
    case params[:exec]
    when "preview"
      puts DigestMailer.create_message(d)
    when "send"
      DigestMailer.deliver_message(d)
      puts "Digest sent, purging database..."
      Tweet.delete(:all)
   else
      puts "valid options: digest -e [preview | send]"
    end
  end
  
  # execute all required actions to setup the application
  # make sure there's no database created before run it.
  def setup
    actions = ["database -e create", "retrieve", "digest -e preview", "digest -e send" ]
    actions.each do |a|
      puts "[#{Time.now}]#{$0} #{a}..."
      Kernel.system("#{$0} #{a}")
      exit if $? != 0
    end
    puts "setup done, now add the following cronjobs in your server:"
    puts "\n"
    puts "\t\t 10 * * * *  #{$0} retrieve"
    puts "\t\t 59 23 * * * #{$0} digest -e mail"
    puts "\n"
  end

end

class View < SimpleConsole::View; end

# Database Migration
class CreateTweets< ActiveRecord::Migration
  def self.up
    create_table :tweets do |t|
      t.column  :screen_name, :string
      t.column  :message,     :text
      t.column  :remote_id,   :integer
      t.column  :created_at,  :datetime
    end
  end

  def self.down
    drop_table :tweets
  end
end

# Connect to the database (sqlite in this case)
ActiveRecord::Base.establish_connection({
      :adapter => "sqlite3", 
      :dbfile => "#{Pathname.new(File.open($0).path).dirname}/tweets.sqlite" 
})

# Setup actionmailer
ActionMailer::Base.smtp_settings = {
  :address        => SMTP_SERVER,
  :port           => SMTP_PORT,
  :user_name      => SMTP_USER,
  :password       => SMTP_PASS,  
  :authentication => :plain
}

# Tweet AR Class
class Tweet < ActiveRecord::Base
end

# DigestMailer AM Class
class DigestMailer < ActionMailer::Base
    def message(digest)
      from EMAIL_ADDRESS
      recipients EMAIL_ADDRESS
      subject "Twitter Digest - #{Date.today}"
      body  digest
    end
end

# Run the app
SimpleConsole::Application.run(ARGV, Controller, View)
