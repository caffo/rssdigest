#!/usr/bin/env ruby
# rssdigest.rb - rss to email digest daemon
# non-copyright (c) 2008 rodrigo franco <caffo@imap.cc>

$:.unshift(File.dirname(__FILE__) + '/../lib')
require 'ssl'
require 'utils'

# Required Gems
require 'rubygems'
require "simpleconsole"
require 'rubygems'
require 'active_record' #(sqlite3)
require 'action_mailer'
require 'openssl'
require 'simple-rss'

# Non Gems required libs
require 'time'
require 'pathname'
require 'open-uri'
require 'cgi'
require 'htmlentities'


# Configuration Variables
FEED_TITLE       = 'AppShopper'
FEED_URL         = 'http://appshopper.com/feed/'

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
    puts "rssdigest.rb"
    puts "--------"
    puts "\n"
    puts "rss to email digest daemon. experimental code, no warranty or"
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
    puts "\t* Edit the configuration variables and run '#{$0} setup'"
    puts "\t* If everything goes OK, follow the instructions after the setup execution. If not, see manual setup."
    puts "\n"
    puts "-------------"
    puts "manual setup"
    puts "-------------"
    puts "\n"
    puts "\t* Create the database using '#{$0} database -e create'"
    puts "\t* Test the retrieval using '#{$0} retrieve'"
    puts "\t* Preview the digest using '#{$0} digest preview'"
    puts "\t* Test the email sending using '#{$0} digest mail'"
    puts "\t* Check your email"
    puts "\t* Add the following cronjobs in your server:"
    puts "\n"
    puts "\t\t 10 * * * *  #{$0} retrieve"
    puts "\t\t 59 23 * * * #{$0} digest -e send"
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
      CreateEntries.migrate(:up)
    when "destroy"
      CreateEntries.migrate(:down)
    else
      puts "valid options: database -e [create | destroy]"
    end
  end

  # retrieve the entries
  # and store them in our database
  def retrieve
    feed  = SimpleRSS.parse open(FEED_URL)
    feed.items.each do |item|
#      p item.inspect
      next if Entry.find_by_remote_id(item.object_id)
      e = Entry.new
      e.title       = item.title
      e.body        = item.content
      e.body        = item.description if item.content.nil?
      e.remote_id   = item.object_id
      e.author      = item.author
      e.save
    end
  end
  
  # prints the total tweets that will be sent
  # in the next digest sending
  def status
    puts "#{Entry.find(:all).size} entries in the queue."
  end
  
  # deal with the email, generating and sending the
  # digests to the user
  def digest
      d     = String.new
      coder = HTMLEntities.new
      
      Entry.find(:all).each do |t|
        next if t.created_at.to_date != Date.today
        d << "<h1>#{t.title}</h1>#{coder.decode(t.body).strip_html(%w(p br a h1 h2 h3 h4 h5 img)).gsub('h1','h2')}"
      end      
  
    case params[:exec]
    when "preview"
      puts DigestMailer.create_message(d)
    when "send"
      DigestMailer.deliver_message(d)
      puts "Digest sent, purging database..."
      Entry.delete(:all)
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
class CreateEntries< ActiveRecord::Migration
  def self.up
    create_table :entries do |t|
      t.column  :title,       :text
      t.column  :author,      :string
      t.column  :body,        :text
      t.column  :remote_id,   :integer
      t.column  :created_at,  :datetime
    end
  end

  def self.down
    drop_table :entries
  end
end

# Connect to the database (sqlite in this case)
ActiveRecord::Base.establish_connection({
      :adapter => "sqlite3", 
      :dbfile => "#{Pathname.new(File.open($0).path).dirname}/entries.sqlite" 
})

# Setup actionmailer
ActionMailer::Base.smtp_settings = {
  :address => SMTP_SERVER,
  :port => SMTP_PORT,
  :user_name => SMTP_USER,
  :password => SMTP_PASS,  
  :authentication => :plain
}

# Tweet AR Class
class Entry < ActiveRecord::Base
end

# DigestMailer AM Class
class DigestMailer < ActionMailer::Base
    def message(digest)
      from 'caffeine@gmail.com'
      recipients 'caffeine@gmail.com'
      subject "#{FEED_TITLE} Digest - #{Date.today}"
      content_type 'text/html'
      body  digest
    end
end

# Run the app
SimpleConsole::Application.run(ARGV, Controller, View)