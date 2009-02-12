require 'rubygems'
require 'sinatra'
require 'dm-core'
require 'id3lib'
require 'fileutils'
require 'tarruby'

unless defined?(ROOT)
  ROOT = File.expand_path(File.dirname(__FILE__))
end

class Song
  include DataMapper::Resource
  property :id, Serial
  property :title, String
  property :disc, Integer
  property :track, Integer
  property :year, Integer
  belongs_to :artist
  belongs_to :album
end

class Album
  include DataMapper::Resource
  property :id, Serial
  property :name, String
  property :compilation, Boolean
  belongs_to :artist
  has n, :songs
end

class Artist
  include DataMapper::Resource
  property :id, Serial
  property :name, String
  has n, :albums
  has n, :songs
end

use Rack::Auth::Basic do |username, password|
  username == 'viking' && password == 'secret'
end

configure do
  DataMapper.setup(:default, "sqlite3:///#{Dir.pwd}/musync.sqlite3")
  DataMapper.auto_migrate!
end

helpers do
  include Rack::Utils
  alias_method :h, :escape_html

  def unescape_html(string)
    string.to_s.gsub("&amp;", "&").
      gsub("&lt;", "<").
      gsub("&gt;", ">").
      gsub("&#39;", "'").
      gsub("&quot;", '"')
  end

  def song_input(song, field, type, value)
    %{<input type="#{type}" name="song[#{song[:which]}][#{field}]" value="#{h(value)}" />}
  end

  def song_text_field(song, field)
    song_input(song, field, "text", song[field])
  end
end

get '/' do
  @songs = Song.all
  haml :index
end

get '/stylesheet.css' do
  content_type 'text/css', :charset => 'utf-8'
  sass :stylesheet
end

post '/upload' do
  # move the tarball to a temporary area, extract all files,
  # then move mp3 files to a staging area for user inspection
  @timestamp  = Time.now.to_i
  tmp_dir     = "%s/tmp/files/%d"   % [ROOT, @timestamp]
  staging_dir = "%s/tmp/staging/%d" % [ROOT, @timestamp]
  src_file    = params[:file][:tempfile].path
  basename    = File.basename(src_file)
  dest_file   = "%s/%s" % [tmp_dir, basename]
  FileUtils.mkdir([tmp_dir, staging_dir])
  FileUtils.mv(src_file, tmp_dir)
  Dir.chdir(tmp_dir) do
    Tar.gzopen(dest_file, File::RDONLY, 0644, Tar::GNU) do |tar|
      tar.extract_all
    end
  end
  FileUtils.rm(dest_file)

  @songs = []
  Dir["#{tmp_dir}/**/*.mp3"].each_with_index do |mp3, i|
    tag = ID3Lib::Tag.new(mp3)
    @songs << {
      :which => i,
      :title => tag.title,
      :disc  => tag.disc.split("/")[0],
      :track => tag.track.split("/")[0],
      :year  => tag.year,
      :artist => tag.artist,
      :album => tag.album
    }
    FileUtils.mv(mp3, "%s/%i.mp3" % [staging_dir, i])
  end
  FileUtils.rm_rf(tmp_dir)

  haml :upload
end

post '/create' do
  staging_dir = "tmp/staging/#{params[:timestamp]}"
  params[:song].each_pair do |which, attribs|
    src_file = "%s/%d.mp3" % [staging_dir, which.to_i]
    attribs.delete_if { |k, v| v.empty? }

    artist = attribs.delete('artist')
    if artist
      artist = Artist.first(:name => artist) || Artist.create(:name => artist)
      attribs['artist_id'] = artist.id
    end

    album = attribs.delete('album')
    if album
      artist_id = artist ? artist_id : nil
      album = Album.first(:name => album, :artist_id => artist_id) ||
        Album.create(:name => album, :artist_id => artist_id)
      attribs['album_id'] = album.id
    end
    song = Song.create(attribs)
    FileUtils.mv(src_file, "songs/%d.mp3" % song.id)
  end
  FileUtils.rm_rf(staging_dir)

  redirect "/"
end

__END__

@@ layout
%html
%head
  %link{:rel => "stylesheet", :href => "/stylesheet.css", :type => "text/css"}/
  %script{:src => "/jquery-1.3.1.min.js", :type => "text/javascript"}
  %title Musync
%body
  = yield

@@ stylesheet
body
  font:
    family: Verdana
    size: 10px
label
  font-weight: bold
table.songs
  th
    font-size: 12px
    border:
      bottom: 2px solid gray
.track, .disc, .year
  input
    width: 4em

@@ index
%h1 Songs
- if @songs.empty?
  There are no songs yet!
- else
  %table.songs
    %tr
      %th.track Track
      %th.title Title
      %th.artist Artist
      %th.album Album
      %th.disc Disc
      %th.year Year
    - @songs.each do |song|
      %tr
        %td.track= song.track
        %td.title= song.title
        %td.artist= song.artist.name
        %td.album= song.album.name
        %td.disc= song.disc
        %td.year= song.year
%br/
%br/
%form{:action => "/upload", :method => "post", :enctype => "multipart/form-data"}
  %p
    %label{:for => 'file'} Upload tarball:
    %input{:type => 'file', :name => 'file', :id => 'file'}/
  %p
    %input{:type => 'submit', :value => "Upload"}

@@ upload
%h1 Upload
%form{:action => "/create", :method => "post"}
  %input{:type => "hidden", :name => "timestamp", :value => @timestamp}/
  %table.songs
    %tr
      %th.track Track
      %th.title Title
      %th.artist Artist
      %th.album Album
      %th.disc Disc
      %th.year Year
    - @songs.each do |song|
      %tr
        %td.track= song_text_field(song, :track)
        %td.title= song_text_field(song, :title)
        %td.artist= song_text_field(song, :artist)
        %td.album= song_text_field(song, :album)
        %td.disc= song_text_field(song, :disc)
        %td.year= song_text_field(song, :year)
  %br/
  %input{:type => "submit", :value => "Create"}/
