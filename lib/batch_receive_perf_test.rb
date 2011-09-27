require 'sinatra'

require 'rack/perftools_profiler'
require 'factory_girl_rails'

class BatchReceivePerfTest
  def initialize
    @object = Factory(:status_message)
    @user_ids = [] 
    5000.times do |t|
      puts t
      u = Factory(:user)
      @user_ids << u.id
      Contact.create(:user_id => u.id, :person_id => @object.author.id) 
    end 
  end



  def run
    PerfTools::CpuProfiler.start(File.join( Rails.root, "/tmp/add_numbers_profile")) do
    
      30.times do |t|
        Postzord::Receiver::LocalBatch.new(@object, @user_ids).perform!
        puts "done with #{t}"
      end
    end
  end
end

class BatchProfiler < Sinatra::Base
  #require 'spec/factories'
  
  configure do
    if User.count < 500
      @object = Factory(:status_message)
      @user_ids = [] 
      5000.times do |t|
        puts t
        u = Factory(:user)
        @user_ids << u.id
        Contact.create(:user_id => u.id, :person_id => @object.author.id) 
      end
    end

    use ::Rack::PerftoolsProfiler, :default_printer => 'pdf', :bundler => true, :mode => :objects
  end

  get "/slow" do
    @object = StatusMessage.first
    @user_ids = User.connection.select_values("select id from users")
 
    Postzord::Receiver::LocalBatch.new(@object, @user_ids).perform!
  end
end
