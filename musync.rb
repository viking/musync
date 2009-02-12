require 'rubygems'
require 'sinatra'
require 'dm-core'
require 'id3lib'

class Song
  include DataMapper::Resource
  property :id, Serial
  property :title, String
end

use Rack::Auth::Basic do |username, password|
  username == 'viking' && password == 'secret'
end

configure do
  DataMapper.setup(:default, "sqlite3:///#{Dir.pwd}/musync.sqlite3")
  DataMapper.auto_migrate!
end

get '/' do
  haml :index
end

post '/upload' do
  dir = "tmp/#{Time.now.to_i}"
  tempfile = params[:file][:tempfile].path
  file = "#{dir}/#{File.basename(tempfile)}"
  system("mkdir", dir)
  system("mv", tempfile, dir)
  system("tar", 'xzf', file, '-C', dir)
  system("rm", file)

  Dir["#{dir}/**/*.mp3"].each do |file|
    tag = ID3Lib::Tag.new(file)
    song = Song.new(:title => tag.title)
    song.save
    system("mv", file, "songs/#{song.id}.mp3")
  end
  system("rm", "-fr", dir)
end

__END__

@@ layout
%html
%head
  %title Musync
%body
  = yield

@@ index
%h1 Songs
%br/
%h2 Upload
%form{:action => "/upload", :method => "post", :enctype => "multipart/form-data"}
  %p
    %label{:for => 'file'} File:
    %input{:type => 'file', :name => 'file', :id => 'file'}/
  %p
    %input{:type => 'submit', :value => "Upload"}
